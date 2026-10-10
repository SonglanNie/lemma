"""Exercise the packaged Chrome host through its actual framed stdin/stdout."""
import base64
import json
import os
import struct
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parent.parent
host = root / "build/Lemma.app/Contents/MacOS/LemmaBrowserHost"
with tempfile.TemporaryDirectory(prefix="lemma-host-check-") as temporary:
    support = Path(temporary)
    request_id = str(uuid.uuid4()).upper()
    packet_dir = support / "Browser" / request_id
    packet_dir.mkdir(parents=True)
    image = bytes(range(251)) * 1500
    packet = {
        "id": request_id, "noteID": str(uuid.uuid4()), "mode": "draft",
        "prompt": "Explain β̂ from this source.",
        "images": [{"name": "source.png", "label": "Source A", "byteCount": len(image)}],
        "createdAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    }
    (packet_dir / "request.json").write_text(json.dumps(packet))
    (packet_dir / "source.png").write_bytes(image)
    environment = dict(os.environ, LEMMA_SUPPORT_DIR=str(support))
    with subprocess.Popen([str(host)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=environment) as process:
        call_id = 0

        def rpc(operation, **fields):
            global call_id
            call_id += 1
            payload = json.dumps(dict(operation=operation, callID=call_id, requestID=request_id, **fields)).encode()
            process.stdin.write(struct.pack("<I", len(payload)) + payload)
            process.stdin.flush()
            header = process.stdout.read(4)
            assert len(header) == 4, "Host did not return a frame"
            response = json.loads(process.stdout.read(struct.unpack("<I", header)[0]))
            assert response["callID"] == call_id, "Response linked to the wrong request"
            return response

        assert rpc("ping")["ok"]
        response = rpc("packet")
        assert response["packet"]["prompt"] == packet["prompt"]
        received = bytearray()
        for index in range(4):
            response = rpc("image", name="source.png", index=index)
            assert response["ok"]
            received.extend(base64.b64decode(response["data"]))
            if response["done"]:
                break
        assert received == image
        assert not rpc("image", name="../workspace.json", index=0)["ok"]
        assert rpc("result", status="complete", answer="$X^\\top X$", conversationURL="https://chatgpt.com/c/test")["ok"]
        saved = json.loads((packet_dir / "result.json").read_text())
        assert saved["requestID"] == request_id and saved["answer"] == "$X^\\top X$"
        process.stdin.close()
        assert process.wait(timeout=5) == 0
print("Packaged native host: framing, Unicode, correlated replies, four image chunks, path restriction, and write-back passed.")
