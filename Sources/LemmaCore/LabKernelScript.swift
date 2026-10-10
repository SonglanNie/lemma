import Foundation

/// The Python side of the Lab: a tiny notebook kernel speaking one JSON object per line.
/// Requests on stdin: {"type":"execute","id":…,"code":…}, {"type":"complete",…} or {"type":"shutdown"}; end of input stops it.
/// Replies on the original stdout: ready, stream, image, result, error and done messages, each tagged with the request id.
/// User output is captured through `sys.stdout`/`sys.stderr`; C-level writes to file descriptor 1 are sent to stderr
/// so they cannot corrupt the protocol. Matplotlib figures are rendered with Agg and returned as PNG after each cell.
///
/// Output is buffered and sent at most every 0.1 s (a flusher thread sends what a quiet cell printed last). A cell's
/// first 20,000 characters stream live; past that only its last 20,000 are kept and sent when it ends, with a count
/// of what was left out, and at most 30 figures are rendered, so `while True: print(i)` cannot flood Lemma.
/// A watcher thread ends the kernel, and anything its cells started, the moment Lemma's process exits.
public enum LabKernelScript {
    public static let version = 3

    public static let source = #"""
# Lemma Lab kernel · runs notebook cells for Lemma over a line-based JSON protocol.
import ast, base64, builtins, collections, io, json, linecache, os, pprint, signal, sys, threading, time, traceback

_protocol = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
os.dup2(2, 1)
_current = {"id": None}
_namespace = {"__name__": "__main__", "__builtins__": builtins}
_count = 0
_kernel_file = os.path.abspath(__file__) if "__file__" in globals() else "<kernel>"
# The main thread and the flusher both write: one lock for the protocol, the stream buffers and the output budget.
_lock = threading.RLock()
_wake = threading.Event()
_HEAD = 20000
_TAIL = 20000
_FIGURES = 30
_output = {}


def _send(message):
    with _lock:
        if "id" not in message:
            message["id"] = _current["id"]
        _protocol.write(json.dumps(message) + "\n")
        _protocol.flush()


def _reset_output():
    with _lock:
        _output.update(sent=0, truncated=False, dropped=0, tail=collections.deque(), tail_size=0, figures=0, skipped=0)


def _emit(name, text):
    """Sends a cell's stream text: the first _HEAD characters as they come, then only the last _TAIL, kept for its end."""
    with _lock:
        room = _HEAD - _output["sent"]
        if room > 0:
            head = text[:room]
            _output["sent"] += len(head)
            _send({"type": "stream", "name": name, "text": head})
            text = text[room:]
        if not text:
            return
        if not _output["truncated"]:
            _output["truncated"] = True
            _send({"type": "stream", "name": "stderr", "text": "\n… output truncated by Lemma; the last lines follow when the cell ends\n"})
        if len(text) > _TAIL:
            _output["dropped"] += len(text) - _TAIL
            text = text[-_TAIL:]
        tail = _output["tail"]
        tail.append((name, text))
        _output["tail_size"] += len(text)
        while _output["tail_size"] > _TAIL:
            first_name, first = tail[0]
            excess = _output["tail_size"] - _TAIL
            if len(first) <= excess:
                tail.popleft()
                _output["tail_size"] -= len(first)
                _output["dropped"] += len(first)
            else:
                tail[0] = (first_name, first[excess:])
                _output["tail_size"] -= excess
                _output["dropped"] += excess


class _Stream(io.TextIOBase):
    def __init__(self, name):
        self.name = name
        self._parts = []
        self._size = 0

    def writable(self):
        return True

    def isatty(self):
        return False

    @property
    def encoding(self):
        return "utf-8"

    def write(self, text):
        if not isinstance(text, str):
            text = str(text)
        if not text:
            return 0
        with _lock:
            self._parts.append(text)
            self._size += len(text)
            full = self._size > 8192
        if full:
            self.flush()
        else:
            _wake.set()
        return len(text)

    def flush(self):
        with _lock:
            if not self._parts:
                return
            text = "".join(self._parts)
            self._parts = []
            self._size = 0
            _emit(self.name, text)


_streams = (_Stream("stdout"), _Stream("stderr"))


def _flusher():
    """Sends what a cell printed within 0.1 s, even when it prints nothing after it; sleeps while nothing is waiting."""
    while True:
        _wake.wait()
        time.sleep(0.1)
        _wake.clear()
        for stream in _streams:
            try:
                stream.flush()
            except Exception:
                pass


def _watch_parent():
    """Ends the kernel when Lemma's process exits, even in the middle of a cell: a kernel never outlives the app."""
    parent = int(os.environ.pop("LEMMA_PARENT_PID", "0") or "0") or os.getppid()
    try:
        import select
        queue = select.kqueue()
        queue.control([select.kevent(parent, filter=select.KQ_FILTER_PROC, flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                                     fflags=select.KQ_NOTE_EXIT)], 0, 0)
        if os.getppid() == 1:
            raise ProcessLookupError
        while not queue.control(None, 1, None):
            pass
    except ProcessLookupError:
        pass
    except Exception:
        while True:
            try:
                os.kill(parent, 0)
            except ProcessLookupError:
                break
            except Exception:
                pass
            time.sleep(1)
    try:
        if os.getpgrp() == os.getpid():
            os.killpg(os.getpid(), signal.SIGKILL)
    finally:
        os._exit(0)


def _flush_figures(*args, **kwargs):
    pyplot = sys.modules.get("matplotlib.pyplot")
    if pyplot is None:
        return
    for number in list(pyplot.get_fignums()):
        if _output.get("figures", 0) >= _FIGURES:
            _output["skipped"] = _output.get("skipped", 0) + 1
            continue
        figure = pyplot.figure(number)
        buffer = io.BytesIO()
        try:
            figure.savefig(buffer, format="png", dpi=144, bbox_inches="tight", facecolor="white")
            _send({"type": "image", "format": "png", "data": base64.b64encode(buffer.getvalue()).decode("ascii")})
            _output["figures"] = _output.get("figures", 0) + 1
        except Exception as error:
            sys.stderr.write("Could not render a figure: %s\n" % error)
    pyplot.close("all")


def _prepare_matplotlib():
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as pyplot
        pyplot.show = _flush_figures
        matplotlib.rcParams.update({"figure.figsize": (6.4, 4.2), "figure.dpi": 100, "axes.spines.top": False,
                                    "axes.spines.right": False, "font.size": 10})
    except Exception:
        pass


def _no_input(prompt=""):
    raise RuntimeError("input() is not available in Lemma's Lab; set the value in the cell instead.")


def _packages():
    import importlib.util
    try:
        from importlib import metadata
    except ImportError:
        metadata = None
    found = {}
    for module, distribution in (("numpy", "numpy"), ("scipy", "scipy"), ("matplotlib", "matplotlib"), ("pandas", "pandas"),
                                 ("sklearn", "scikit-learn"), ("sympy", "sympy"), ("statsmodels", "statsmodels")):
        if importlib.util.find_spec(module) is None:
            continue
        version = ""
        if metadata is not None:
            try:
                version = metadata.version(distribution)
            except Exception:
                version = ""
        found[module] = version
    return found


def _repr(value):
    try:
        if isinstance(value, (dict, list, tuple, set)) and len(repr(value)) > 100:
            text = pprint.pformat(value, width=100, compact=True)
        else:
            text = repr(value)
    except Exception as error:
        text = "<unprintable %s: %s>" % (type(value).__name__, error)
    return text if len(text) <= 20000 else text[:20000] + "\n…"


def _flush_streams():
    for stream in (sys.stdout, sys.stderr) + _streams:
        try:
            stream.flush()
        except Exception:
            pass


def _finish_output():
    """Ends a cell's text output: what is buffered, then what the budget held back, last lines included."""
    _flush_streams()
    with _lock:
        if _output.get("dropped"):
            _send({"type": "stream", "name": "stderr", "text": "… %s characters not shown\n" % format(_output["dropped"], ",")})
        merged = []
        for name, text in _output.get("tail", ()):
            if merged and merged[-1][0] == name:
                merged[-1][1].append(text)
            else:
                merged.append((name, [text]))
        for name, parts in merged:
            _send({"type": "stream", "name": name, "text": "".join(parts)})
        if _output.get("skipped"):
            _send({"type": "stream", "name": "stderr",
                   "text": "… %d more figures not shown (Lemma shows %d per cell)\n" % (_output["skipped"], _FIGURES)})
        _output.update(dropped=0, tail=collections.deque(), tail_size=0, skipped=0)


def _traceback(error):
    frames = [frame for frame in traceback.extract_tb(error.__traceback__) if os.path.abspath(frame.filename) != _kernel_file]
    lines = traceback.format_list(frames) + traceback.format_exception_only(type(error), error)
    return "".join(lines).rstrip()


def _run(request):
    global _count
    _current["id"] = request.get("id")
    _count += 1
    _reset_output()
    code = request.get("code", "")
    name = "<cell %d>" % _count
    linecache.cache[name] = (len(code), None, code.splitlines(True), name)
    status = "ok"
    started = time.monotonic()
    try:
        tree = ast.parse(code, filename=name, mode="exec")
        last = None
        if tree.body and isinstance(tree.body[-1], ast.Expr):
            last = ast.Expression(tree.body.pop().value)
        exec(compile(tree, name, "exec"), _namespace)
        if last is not None:
            value = eval(compile(last, name, "eval"), _namespace)
            if value is not None:
                _namespace["_"] = value
                _finish_output()
                _send({"type": "result", "text": _repr(value)})
    except KeyboardInterrupt:
        status = "interrupted"
        _finish_output()
        _send({"type": "error", "ename": "KeyboardInterrupt", "evalue": "Interrupted by the reader", "traceback": ""})
    except SystemExit as error:
        status = "error"
        _finish_output()
        _send({"type": "error", "ename": "SystemExit", "evalue": str(error.code), "traceback": ""})
    except BaseException as error:
        status = "error"
        _finish_output()
        _send({"type": "error", "ename": type(error).__name__, "evalue": str(error), "traceback": _traceback(error)})
    finally:
        try:
            _flush_streams()
            _flush_figures()
            _finish_output()
        except KeyboardInterrupt:
            pass
        _send({"type": "done", "status": status, "count": _count, "duration": time.monotonic() - started})
        _current["id"] = None


def _complete(request):
    text = request.get("text", "")
    matches = []
    try:
        import rlcompleter
        completer = rlcompleter.Completer(_namespace)
        for state in range(300):
            match = completer.complete(text, state)
            if match is None:
                break
            matches.append(match)
    except Exception:
        matches = []
    seen = set()
    unique = [m for m in matches if not (m in seen or seen.add(m))]
    _send({"type": "completions", "id": request.get("id"), "text": text, "matches": unique[:200]})


def _main():
    threading.Thread(target=_watch_parent, name="lemma-parent", daemon=True).start()
    threading.Thread(target=_flusher, name="lemma-output", daemon=True).start()
    builtins.input = _no_input
    sys.stdout, sys.stderr = _streams
    _reset_output()
    _prepare_matplotlib()
    _send({"type": "ready", "python": sys.version.split()[0], "executable": sys.executable, "packages": _packages()})
    while True:
        try:
            line = sys.stdin.readline()
        except KeyboardInterrupt:
            continue
        if not line:
            break
        try:
            request = json.loads(line)
        except ValueError:
            continue
        kind = request.get("type", "execute")
        if kind == "shutdown":
            break
        if kind == "complete":
            _complete(request)
            continue
        if kind == "execute":
            try:
                _run(request)
            except KeyboardInterrupt:
                _send({"type": "done", "status": "interrupted", "count": _count, "duration": 0})


_main()
"""#
}
