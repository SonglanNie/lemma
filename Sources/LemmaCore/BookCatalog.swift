import Foundation

/// Books whose authors or publishers distribute the whole PDF free of charge, checked on 1 October 2026 (each PDF
/// fetched and found to start with %PDF). Lemma downloads one only when the reader asks, from its official address.
public struct CatalogBook: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let authors: [String]
    public let edition: String?
    public let year: Int
    public let subject: String
    public let level: String
    public let summary: String
    public let pdf: URL
    public let homepage: URL
    public let license: String
    public let bytes: Int?

    public var authorLine: String {
        switch authors.count {
        case 0: ""
        case 1: authors[0]
        case 2: authors.joined(separator: " and ")
        default: authors.dropLast().joined(separator: ", ") + " and " + authors.last!
        }
    }
    public var sizeText: String? { bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } }
}

public enum BookCatalog {
    public static let books: [CatalogBook] = [
        CatalogBook(id: "basic-analysis", title: "Basic Analysis I", subtitle: "Introduction to Real Analysis, Volume I", authors: ["Jiří Lebl"], edition: "Version 6.3 (May 2026)", year: 2026, subject: "Analysis", level: "Undergraduate",
                    summary: "First course in real analysis: real numbers, sequences and series, continuity, derivatives, the Riemann integral and sequences of functions.",
                    pdf: URL(string: "https://www.jirka.org/ra/realanal.pdf")!, homepage: URL(string: "https://www.jirka.org/ra/")!,
                    license: "CC BY-NC-SA 4.0 or CC BY-SA 4.0 (dual-licensed)", bytes: 1901622),
        CatalogBook(id: "mira", title: "Measure, Integration & Real Analysis", subtitle: nil, authors: ["Sheldon Axler"], edition: nil, year: 2020, subject: "Analysis", level: "Graduate",
                    summary: "Graduate real analysis: Lebesgue measure and integration, product measures, Banach and Hilbert spaces, Fourier analysis and probability.",
                    pdf: URL(string: "https://measure.axler.net/MIRA.pdf")!, homepage: URL(string: "https://measure.axler.net/")!,
                    license: "CC BY-NC 4.0 (Springer open access)", bytes: 3539121),
        CatalogBook(id: "what-if", title: "Causal Inference: What If", subtitle: nil, authors: ["Miguel A. Hernán", "James M. Robins"], edition: "Revision of 19 Aug 2026", year: 2020, subject: "Causal Inference", level: "Graduate",
                    summary: "Causal inference from observational data: counterfactuals, confounding, IP weighting, g-methods and time-varying treatments, with code online.",
                    pdf: URL(string: "https://miguelhernan.org/s/hernanrobins_WhatIf_19aug26.pdf")!, homepage: URL(string: "https://miguelhernan.org/whatifbook")!,
                    license: "Free PDF from the authors' site", bytes: 11315465),
        CatalogBook(id: "eci", title: "Elements of Causal Inference", subtitle: "Foundations and Learning Algorithms", authors: ["Jonas Peters", "Dominik Janzing", "Bernhard Schölkopf"], edition: nil, year: 2017, subject: "Causal Inference", level: "Graduate",
                    summary: "Structural causal models, interventions and counterfactuals, and learning cause-effect structure from data, with a machine-learning outlook.",
                    pdf: URL(string: "https://mitp-content-server.mit.edu/books/content/sectbyfn?collid=books_pres_0&id=11283&fn=11283.pdf")!, homepage: URL(string: "https://people.math.ethz.ch/~jopeters/elements.html")!,
                    license: "CC BY-NC-ND 4.0 (MIT Press open access)", bytes: 27169482),
        CatalogBook(id: "erickson-algorithms", title: "Algorithms", subtitle: nil, authors: ["Jeff Erickson"], edition: "1st edition", year: 2019, subject: "Computer Science", level: "Undergraduate",
                    summary: "Algorithm design through recursion, backtracking, dynamic programming, greedy methods, graph algorithms and NP-hardness, written for students.",
                    pdf: URL(string: "https://jeffe.cs.illinois.edu/teaching/algorithms/book/Algorithms-JeffE.pdf")!, homepage: URL(string: "https://jeffe.cs.illinois.edu/teaching/algorithms/")!,
                    license: "CC BY 4.0", bytes: 25055430),
        CatalogBook(id: "fds", title: "Foundations of Data Science", subtitle: nil, authors: ["Avrim Blum", "John Hopcroft", "Ravindran Kannan"], edition: "Pre-publication version", year: 2020, subject: "Computer Science", level: "Graduate",
                    summary: "Theory behind modern data analysis: high-dimensional geometry, SVD, random walks, learning, streaming algorithms, clustering and random graphs.",
                    pdf: URL(string: "https://home.ttic.edu/~avrim/book.pdf")!, homepage: URL(string: "https://home.ttic.edu/~avrim/")!,
                    license: "Free pre-publication PDF for personal use (published by Cambridge University Press)", bytes: 2546388),
        CatalogBook(id: "mcs", title: "Mathematics for Computer Science", subtitle: nil, authors: ["Eric Lehman", "F. Thomson Leighton", "Albert R. Meyer"], edition: nil, year: 2018, subject: "Computer Science", level: "Undergraduate",
                    summary: "Discrete mathematics for computer scientists: proofs, induction, number theory, graphs, counting, discrete probability and recurrences.",
                    pdf: URL(string: "https://courses.csail.mit.edu/6.042/spring18/mcs.pdf")!, homepage: URL(string: "https://ocw.mit.edu/courses/6-1200j-mathematics-for-computer-science-spring-2024/pages/readings/")!,
                    license: "CC BY-SA", bytes: 13269308),
        CatalogBook(id: "d2l", title: "Dive into Deep Learning", subtitle: nil, authors: ["Aston Zhang", "Zachary C. Lipton", "Mu Li", "Alexander J. Smola"], edition: nil, year: 2023, subject: "Deep Learning", level: "Undergraduate",
                    summary: "Hands-on deep learning with runnable code: MLPs, CNNs, RNNs, attention and transformers, optimization, computer vision and NLP.",
                    pdf: URL(string: "https://d2l.ai/d2l-en.pdf")!, homepage: URL(string: "https://d2l.ai/")!,
                    license: "CC BY-SA 4.0", bytes: 44685994),
        CatalogBook(id: "udl", title: "Understanding Deep Learning", subtitle: nil, authors: ["Simon J. D. Prince"], edition: "Online version (9 Feb 2026)", year: 2023, subject: "Deep Learning", level: "Undergraduate",
                    summary: "Clear, figure-rich account of deep learning: training and generalization, CNNs, transformers, GNNs, GANs, flows, VAEs, diffusion models and RL.",
                    pdf: URL(string: "https://github.com/udlbook/udlbook/releases/download/v5.0.3/UnderstandingDeepLearning_02_09_26_C.pdf")!, homepage: URL(string: "https://udlbook.github.io/udlbook/")!,
                    license: "CC BY-NC-ND 4.0", bytes: 22344992),
        CatalogBook(id: "polyanskiy-wu", title: "Information Theory", subtitle: "From Coding to Learning", authors: ["Yury Polyanskiy", "Yihong Wu"], edition: "Pre-publication draft", year: 2025, subject: "Information Theory", level: "Graduate",
                    summary: "Modern information theory: information measures, data compression, channel coding, and information-theoretic methods in statistics and learning.",
                    pdf: URL(string: "https://people.lids.mit.edu/yp/homepage/data/itbook-export.pdf")!, homepage: URL(string: "https://people.lids.mit.edu/yp/homepage/papers.shtml")!,
                    license: "Free pre-publication PDF for personal use (published by Cambridge University Press)", bytes: 5523972),
        CatalogBook(id: "itila", title: "Information Theory, Inference, and Learning Algorithms", subtitle: nil, authors: ["David J. C. MacKay"], edition: "Fourth printing (2005)", year: 2003, subject: "Information Theory", level: "Graduate",
                    summary: "Information theory and Bayesian inference side by side: compression, noisy channels, error-correcting codes, Monte Carlo methods and neural networks.",
                    pdf: URL(string: "https://www.inference.org.uk/itprnn/book.pdf")!, homepage: URL(string: "https://www.inference.org.uk/itprnn/book.html")!,
                    license: "Free PDF for on-screen viewing, © Cambridge University Press", bytes: 11675219),
        CatalogBook(id: "vmls", title: "Introduction to Applied Linear Algebra", subtitle: "Vectors, Matrices, and Least Squares", authors: ["Stephen Boyd", "Lieven Vandenberghe"], edition: nil, year: 2018, subject: "Linear Algebra", level: "Introductory",
                    summary: "Applied first course built around vectors, matrices and least squares, with data fitting, classification and control examples; minimal prerequisites.",
                    pdf: URL(string: "https://web.stanford.edu/~boyd/vmls/vmls.pdf")!, homepage: URL(string: "https://web.stanford.edu/~boyd/vmls/")!,
                    license: "Free PDF, © Cambridge University Press (posted with permission)", bytes: 7061628),
        CatalogBook(id: "hefferon", title: "Linear Algebra", subtitle: nil, authors: ["Jim Hefferon"], edition: "4th edition", year: 2020, subject: "Linear Algebra", level: "Introductory",
                    summary: "First course in linear algebra that builds proof skills: linear systems, vector spaces, linear maps, determinants and eigenvalues, with many exercises.",
                    pdf: URL(string: "https://jheffero.w3.uvm.edu/linearalgebra/book.pdf")!, homepage: URL(string: "https://hefferon.net/linearalgebra/")!,
                    license: "GNU FDL or CC BY-SA 3.0 US (reader's choice)", bytes: 7626685),
        CatalogBook(id: "ladr", title: "Linear Algebra Done Right", subtitle: nil, authors: ["Sheldon Axler"], edition: "4th edition", year: 2024, subject: "Linear Algebra", level: "Undergraduate",
                    summary: "A proof-based second course that develops vector spaces, linear maps, eigenvalues and inner product spaces without leaning on determinants.",
                    pdf: URL(string: "https://linear.axler.net/LADR4e.pdf")!, homepage: URL(string: "https://linear.axler.net/")!,
                    license: "CC BY-NC (Springer open access)", bytes: 2795156),
        CatalogBook(id: "ladw", title: "Linear Algebra Done Wrong", subtitle: nil, authors: ["Sergei Treil"], edition: "Version of 31 Aug 2026", year: 2026, subject: "Linear Algebra", level: "Undergraduate",
                    summary: "Rigorous course for math majors: linear maps, determinants, spectral theory, inner product spaces, quadratic forms, dual spaces and tensors.",
                    pdf: URL(string: "https://www.math.brown.edu/~treil/papers/LADW/LADW_2026_08-31.pdf")!, homepage: URL(string: "https://sites.google.com/a/brown.edu/sergei-treil-homepage/linear-algebra-done-wrong")!,
                    license: "CC BY-NC-ND 3.0", bytes: 1329001),
        CatalogBook(id: "bandit-algorithms", title: "Bandit Algorithms", subtitle: nil, authors: ["Tor Lattimore", "Csaba Szepesvári"], edition: nil, year: 2020, subject: "Machine Learning", level: "Graduate",
                    summary: "Comprehensive theory of multi-armed bandits: stochastic and adversarial bandits, UCB, Thompson sampling, linear and contextual bandits, lower bounds.",
                    pdf: URL(string: "https://tor-lattimore.com/downloads/book/book.pdf")!, homepage: URL(string: "https://tor-lattimore.com/")!,
                    license: "Free PDF from the authors (published by Cambridge University Press)", bytes: 5400750),
        CatalogBook(id: "brml", title: "Bayesian Reasoning and Machine Learning", subtitle: nil, authors: ["David Barber"], edition: "Online version (March 2025)", year: 2012, subject: "Machine Learning", level: "Graduate",
                    summary: "Machine learning through probabilistic graphical models: inference, learning, latent-variable and dynamical models, and approximate inference.",
                    pdf: URL(string: "http://web4.cs.ucl.ac.uk/staff/D.Barber/textbook/180325.pdf")!, homepage: URL(string: "http://web4.cs.ucl.ac.uk/staff/D.Barber/pmwiki/pmwiki.php?n=Brml.Online")!,
                    license: "Free online version from the author (published by Cambridge University Press)", bytes: 15684077),
        CatalogBook(id: "dsml", title: "Data Science and Machine Learning", subtitle: "Mathematical and Statistical Methods", authors: ["Dirk P. Kroese", "Zdravko I. Botev", "Thomas Taimre", "Radislav Vaisman"], edition: "1st edition (updated PDF)", year: 2019, subject: "Machine Learning", level: "Graduate",
                    summary: "Mathematical treatment of data science: Monte Carlo, statistical learning, regression, kernels, classification, trees and deep learning, with Python code.",
                    pdf: URL(string: "https://people.smp.uq.edu.au/DirkKroese/DSML/DSML.pdf")!, homepage: URL(string: "https://people.smp.uq.edu.au/DirkKroese/DSML/")!,
                    license: "Free PDF of the 1st edition from the authors (educational and self-study use)", bytes: 21072005),
        CatalogBook(id: "gpml", title: "Gaussian Processes for Machine Learning", subtitle: nil, authors: ["Carl Edward Rasmussen", "Christopher K. I. Williams"], edition: "Web version of the 2nd printing", year: 2006, subject: "Machine Learning", level: "Graduate",
                    summary: "Gaussian process regression and classification, covariance functions, model selection, approximation methods and links to kernel machines.",
                    pdf: URL(string: "https://gaussianprocess.org/gpml/chapters/RW.pdf")!, homepage: URL(string: "https://gaussianprocess.org/gpml/chapters/")!,
                    license: "Free PDF, posted with permission of MIT Press", bytes: 4052292),
        CatalogBook(id: "ltfp", title: "Learning Theory from First Principles", subtitle: nil, authors: ["Francis Bach"], edition: "Author's final version (May 2025)", year: 2024, subject: "Machine Learning", level: "Graduate",
                    summary: "Learning theory with complete proofs: empirical risk minimization, kernel methods, optimization for ML, local averaging, sparsity and neural networks.",
                    pdf: URL(string: "https://www.di.ens.fr/~fbach/ltfp_book.pdf")!, homepage: URL(string: "https://www.di.ens.fr/~fbach/")!,
                    license: "Free PDF from the author (published by MIT Press)", bytes: nil),
        CatalogBook(id: "mml", title: "Mathematics for Machine Learning", subtitle: nil, authors: ["Marc Peter Deisenroth", "A. Aldo Faisal", "Cheng Soon Ong"], edition: nil, year: 2020, subject: "Machine Learning", level: "Undergraduate",
                    summary: "Linear algebra, analytic geometry, matrix decompositions, vector calculus, probability and optimization, applied to regression, PCA, GMMs and SVMs.",
                    pdf: URL(string: "https://mml-book.github.io/book/mml-book.pdf")!, homepage: URL(string: "https://mml-book.github.io/")!,
                    license: "Free PDF from the authors (published by Cambridge University Press)", bytes: 17565898),
        CatalogBook(id: "prml", title: "Pattern Recognition and Machine Learning", subtitle: nil, authors: ["Christopher M. Bishop"], edition: nil, year: 2006, subject: "Machine Learning", level: "Graduate",
                    summary: "A Bayesian view of machine learning: probability distributions, linear models, kernels, graphical models, mixtures and EM, and approximate inference.",
                    pdf: URL(string: "https://www.microsoft.com/en-us/research/wp-content/uploads/2006/01/Bishop-Pattern-Recognition-and-Machine-Learning-2006.pdf")!, homepage: URL(string: "https://www.microsoft.com/en-us/research/publication/pattern-recognition-machine-learning/")!,
                    license: "Free PDF from Microsoft Research (published by Springer)", bytes: 18090775),
        CatalogBook(id: "ppa", title: "Patterns, Predictions, and Actions", subtitle: "Foundations of Machine Learning", authors: ["Moritz Hardt", "Benjamin Recht"], edition: "Online preprint", year: 2022, subject: "Machine Learning", level: "Graduate",
                    summary: "Machine learning from prediction to action: decision theory, optimization, generalization, datasets, causality and sequential decision making.",
                    pdf: URL(string: "https://mlstory.org/pdf/patterns.pdf")!, homepage: URL(string: "https://mlstory.org/")!,
                    license: "CC BY-NC-ND 4.0", bytes: 2002212),
        CatalogBook(id: "pml-advanced", title: "Probabilistic Machine Learning", subtitle: "Advanced Topics", authors: ["Kevin P. Murphy"], edition: "Online draft (2025-12-10)", year: 2023, subject: "Machine Learning", level: "Graduate",
                    summary: "Research-level sequel: approximate inference, generative models (VAEs, flows, diffusion), causality, decision making and reinforcement learning.",
                    pdf: URL(string: "https://github.com/probml/pml2-book/releases/latest/download/book2.pdf")!, homepage: URL(string: "https://probml.github.io/pml-book/book2.html")!,
                    license: "CC BY-NC-ND", bytes: 151421194),
        CatalogBook(id: "pml-intro", title: "Probabilistic Machine Learning", subtitle: "An Introduction", authors: ["Kevin P. Murphy"], edition: "Online draft (2025-04-18)", year: 2022, subject: "Machine Learning", level: "Graduate",
                    summary: "Broad probabilistic treatment of ML: probability, statistics, linear and logistic regression, neural networks, trees, kernels and unsupervised learning.",
                    pdf: URL(string: "https://github.com/probml/pml-book/releases/latest/download/book1.pdf")!, homepage: URL(string: "https://probml.github.io/pml-book/book1.html")!,
                    license: "CC BY-NC-ND", bytes: 92323940),
        CatalogBook(id: "sutton-barto", title: "Reinforcement Learning", subtitle: "An Introduction", authors: ["Richard S. Sutton", "Andrew G. Barto"], edition: "2nd edition", year: 2018, subject: "Machine Learning", level: "Graduate",
                    summary: "The standard introduction to reinforcement learning: bandits, MDPs, dynamic programming, Monte Carlo, TD learning, function approximation, policy gradients.",
                    pdf: URL(string: "http://incompleteideas.net/book/RLbook2020.pdf")!, homepage: URL(string: "http://incompleteideas.net/book/the-book-2nd.html")!,
                    license: "Free PDF from the authors' site (MIT Press)", bytes: 73129769),
        CatalogBook(id: "uml", title: "Understanding Machine Learning", subtitle: "From Theory to Algorithms", authors: ["Shai Shalev-Shwartz", "Shai Ben-David"], edition: nil, year: 2014, subject: "Machine Learning", level: "Graduate",
                    summary: "Learning theory made concrete: PAC learning, VC dimension, regularization and stability, convex learning, SGD, kernels, boosting and more.",
                    pdf: URL(string: "https://www.cs.huji.ac.il/~shais/UnderstandingMachineLearning/understanding-machine-learning-theory-algorithms.pdf")!, homepage: URL(string: "https://www.cs.huji.ac.il/~shais/UnderstandingMachineLearning/copy.html")!,
                    license: "Free PDF for personal use, posted with permission of Cambridge University Press", bytes: 2601512),
        CatalogBook(id: "convex-optimization", title: "Convex Optimization", subtitle: nil, authors: ["Stephen Boyd", "Lieven Vandenberghe"], edition: nil, year: 2004, subject: "Optimization", level: "Graduate",
                    summary: "Convex sets and functions, duality, and interior-point methods, with applications to approximation, statistical estimation and geometric problems.",
                    pdf: URL(string: "https://web.stanford.edu/~boyd/cvxbook/bv_cvxbook.pdf")!, homepage: URL(string: "https://web.stanford.edu/~boyd/cvxbook/")!,
                    license: "Free PDF, © Cambridge University Press (posted with permission)", bytes: 6881335),
        CatalogBook(id: "hazan-oco", title: "Introduction to Online Convex Optimization", subtitle: nil, authors: ["Elad Hazan"], edition: "2nd edition (arXiv version, Aug 2023)", year: 2022, subject: "Optimization", level: "Graduate",
                    summary: "Optimization as a repeated game: online gradient descent, regularization, bandit feedback, projection-free and adaptive methods (AdaGrad), boosting.",
                    pdf: URL(string: "https://arxiv.org/pdf/1909.05207")!, homepage: URL(string: "https://sites.google.com/view/intro-oco/")!,
                    license: "Free author's version on arXiv (2nd edition published by MIT Press)", bytes: 5394870),
        CatalogBook(id: "hdp", title: "High-Dimensional Probability", subtitle: "An Introduction with Applications in Data Science", authors: ["Roman Vershynin"], edition: "2nd edition", year: 2026, subject: "Probability", level: "Graduate",
                    summary: "Concentration inequalities, random vectors and matrices, and stochastic processes, applied to covariance estimation, sparse recovery and learning.",
                    pdf: URL(string: "https://www.math.uci.edu/~rvershyn/papers/HDP-book/HDP-2.pdf")!, homepage: URL(string: "https://www.math.uci.edu/~rvershyn/papers/HDP-book/HDP-book.html")!,
                    license: "Free PDF from the author (published by Cambridge University Press)", bytes: 5634526),
        CatalogBook(id: "grinstead-snell", title: "Introduction to Probability", subtitle: nil, authors: ["Charles M. Grinstead", "J. Laurie Snell"], edition: "2nd revised edition (GNU FDL version)", year: 1997, subject: "Probability", level: "Introductory",
                    summary: "First course in probability: discrete and continuous distributions, expectation, limit theorems, generating functions, Markov chains and random walks.",
                    pdf: URL(string: "https://math.dartmouth.edu/~prob/prob/prob.pdf")!, homepage: URL(string: "https://chance.dartmouth.edu/teaching_aids/books_articles/probability_book/book.html")!,
                    license: "GNU FDL", bytes: 2993135),
        CatalogBook(id: "mcmt", title: "Markov Chains and Mixing Times", subtitle: nil, authors: ["David A. Levin", "Yuval Peres"], edition: "2nd edition", year: 2017, subject: "Probability", level: "Graduate",
                    summary: "How fast Markov chains converge to equilibrium: coupling, strong stationary times, spectral methods, cutoff, with many examples and exercises.",
                    pdf: URL(string: "https://pages.uoregon.edu/dlevin/MARKOV/mcmt2e.pdf")!, homepage: URL(string: "https://pages.uoregon.edu/dlevin/MARKOV/")!,
                    license: "Free PDF from the authors (published by the American Mathematical Society)", bytes: 4855824),
        CatalogBook(id: "ps4ds", title: "Probability and Statistics for Data Science", subtitle: nil, authors: ["Carlos Fernandez-Granda"], edition: "Pre-publication version", year: 2025, subject: "Probability", level: "Undergraduate",
                    summary: "Probability and statistics taught side by side for data science, illustrated with real datasets, from random variables to estimation and regression.",
                    pdf: URL(string: "https://github.com/cfgranda/ps4ds/raw/main/ps4ds_preprint.pdf")!, homepage: URL(string: "https://www.ps4ds.net/")!,
                    license: "Free pre-publication PDF for personal use (published by Cambridge University Press)", bytes: 15449288),
        CatalogBook(id: "durrett-pte", title: "Probability: Theory and Examples", subtitle: nil, authors: ["Rick Durrett"], edition: "5th edition", year: 2019, subject: "Probability", level: "Graduate",
                    summary: "Measure-theoretic probability: laws of large numbers, central limit theorems, martingales, Markov chains, ergodic theorems and Brownian motion.",
                    pdf: URL(string: "https://sites.math.duke.edu/~rtd/PTE/PTE5_011119.pdf")!, homepage: URL(string: "https://sites.math.duke.edu/~rtd/PTE/pte.html")!,
                    license: "Free PDF from the author's site (published by Cambridge University Press)", bytes: 2195717),
        CatalogBook(id: "aata", title: "Abstract Algebra", subtitle: "Theory and Applications", authors: ["Thomas W. Judson"], edition: "Version of 11 Aug 2026", year: 2026, subject: "Proofs & Algebra", level: "Undergraduate",
                    summary: "Groups, rings and fields with applications to coding theory, cryptography and Galois theory, with optional Sage computations.",
                    pdf: URL(string: "https://judsonbooks.org/aata-files/aata-20260811.pdf")!, homepage: URL(string: "https://judsonbooks.org/abstract-algebra-theory-and-applications/")!,
                    license: "GNU FDL 1.3", bytes: 1685417),
        CatalogBook(id: "book-of-proof", title: "Book of Proof", subtitle: nil, authors: ["Richard Hammack"], edition: "3rd edition", year: 2018, subject: "Proofs & Algebra", level: "Introductory",
                    summary: "Gentle introduction to proofs: logic, sets, direct proof, contradiction, induction, relations, functions and cardinality, with many exercises.",
                    pdf: URL(string: "https://richardhammack.github.io/BookOfProof/Main.pdf")!, homepage: URL(string: "https://richardhammack.github.io/BookOfProof/")!,
                    license: "CC BY-NC-ND 4.0", bytes: 1841432),
        CatalogBook(id: "matrix-cookbook", title: "The Matrix Cookbook", subtitle: nil, authors: ["Kaare Brandt Petersen", "Michael Syskind Pedersen"], edition: "Version of 15 Nov 2012", year: 2012, subject: "Reference", level: "Graduate",
                    summary: "Desk reference of matrix identities: derivatives, inverses, decompositions, determinants, and formulas for Gaussians and other distributions.",
                    pdf: URL(string: "https://www2.compute.dtu.dk/pubdb/edoc/imm3274.pdf")!, homepage: URL(string: "https://www2.compute.dtu.dk/pubdb/pubs/3274-full.html")!,
                    license: "Free PDF from DTU (the authors' institution)", bytes: 692685),
        CatalogBook(id: "ada", title: "Advanced Data Analysis from an Elementary Point of View", subtitle: nil, authors: ["Cosma Rohilla Shalizi"], edition: "Draft of 29 Jan 2026", year: 2026, subject: "Statistics", level: "Undergraduate",
                    summary: "Modern applied statistics after linear regression: smoothing, the bootstrap, additive models, density estimation, causal inference and time series.",
                    pdf: URL(string: "https://www.stat.cmu.edu/~cshalizi/ADAfaEPoV/ADAfaEPoV.pdf")!, homepage: URL(string: "https://www.stat.cmu.edu/~cshalizi/ADAfaEPoV/")!,
                    license: "Free draft PDF from the author", bytes: 17750177),
        CatalogBook(id: "bda3", title: "Bayesian Data Analysis", subtitle: nil, authors: ["Andrew Gelman", "John B. Carlin", "Hal S. Stern", "David B. Dunson", "Aki Vehtari", "Donald B. Rubin"], edition: "3rd edition", year: 2013, subject: "Statistics", level: "Graduate",
                    summary: "Applied Bayesian statistics: hierarchical models, model checking, MCMC and variational computation, regression, GLMs, mixtures and nonparametrics.",
                    pdf: URL(string: "https://sites.stat.columbia.edu/gelman/book/BDA3.pdf")!, homepage: URL(string: "https://sites.stat.columbia.edu/gelman/book/")!,
                    license: "Free PDF for non-commercial use, from the authors", bytes: 55911785),
        CatalogBook(id: "casi", title: "Computer Age Statistical Inference", subtitle: "Algorithms, Evidence, and Data Science", authors: ["Bradley Efron", "Trevor Hastie"], edition: "Corrected online version (March 2021)", year: 2016, subject: "Statistics", level: "Graduate",
                    summary: "How computation reshaped statistics: frequentist, Bayesian and Fisherian inference, empirical Bayes, the bootstrap, MCMC and post-selection inference.",
                    pdf: URL(string: "https://drive.google.com/uc?export=download&id=1--hEc7dt-bfMxF-qhKsPuDxDEVJzLalS")!, homepage: URL(string: "https://hastie.su.domains/CASI/")!,
                    license: "Free PDF for personal use (published by Cambridge University Press)", bytes: 8908337),
        CatalogBook(id: "esl", title: "The Elements of Statistical Learning", subtitle: "Data Mining, Inference, and Prediction", authors: ["Trevor Hastie", "Robert Tibshirani", "Jerome Friedman"], edition: "2nd edition, 12th printing (Jan 2017)", year: 2009, subject: "Statistics", level: "Graduate",
                    summary: "The classic graduate reference on supervised and unsupervised learning: linear methods, trees, boosting, kernels, neural nets and model assessment.",
                    pdf: URL(string: "https://drive.google.com/uc?export=download&id=1--Wo5Hcl2y_v3DL-tGgcJHRPdtjiVYjS")!, homepage: URL(string: "https://hastie.su.domains/ElemStatLearn/")!,
                    license: "Free PDF from the authors, © Springer (posted with permission)", bytes: 13399454),
        CatalogBook(id: "isl-python", title: "An Introduction to Statistical Learning", subtitle: "with Applications in Python", authors: ["Gareth James", "Daniela Witten", "Trevor Hastie", "Robert Tibshirani", "Jonathan Taylor"], edition: "Python edition", year: 2023, subject: "Statistics", level: "Undergraduate",
                    summary: "The Python edition of ISL: the same statistical learning methods, from linear regression to deep learning, with Python labs in every chapter.",
                    pdf: URL(string: "https://drive.google.com/uc?export=download&id=1ajFkHO6zjrdGNqhqW1jKBZdiNGh_8YQ1")!, homepage: URL(string: "https://www.statlearning.com/")!,
                    license: "Free PDF from the authors' site (published by Springer)", bytes: 20053984),
        CatalogBook(id: "isl-r", title: "An Introduction to Statistical Learning", subtitle: "with Applications in R", authors: ["Gareth James", "Daniela Witten", "Trevor Hastie", "Robert Tibshirani"], edition: "2nd edition (corrected June 2023)", year: 2021, subject: "Statistics", level: "Undergraduate",
                    summary: "Accessible introduction to regression, classification, resampling, trees, SVMs, deep learning and survival analysis, with R labs in every chapter.",
                    pdf: URL(string: "https://drive.google.com/uc?export=download&id=1--811-yIIvjT3dvnyFJM20rj_-tbB3bg")!, homepage: URL(string: "https://www.statlearning.com/")!,
                    license: "Free PDF from the authors' site (published by Springer)", bytes: 25136781),
        CatalogBook(id: "openintro-stats", title: "OpenIntro Statistics", subtitle: nil, authors: ["David M. Diez", "Mine Çetinkaya-Rundel", "Christopher D. Barr"], edition: "4th edition (screen-reader PDF)", year: 2019, subject: "Statistics", level: "Introductory",
                    summary: "Introductory statistics: data, probability, distributions, inference for proportions and means, and linear, multiple and logistic regression.",
                    pdf: URL(string: "https://www.openintro.org/go/?id=os4_for_screen_reader")!, homepage: URL(string: "https://www.openintro.org/book/os/")!,
                    license: "CC BY-SA 3.0", bytes: 20947445),
        CatalogBook(id: "sls", title: "Statistical Learning with Sparsity", subtitle: "The Lasso and Generalizations", authors: ["Trevor Hastie", "Robert Tibshirani", "Martin Wainwright"], edition: "Corrected online version (July 2016)", year: 2015, subject: "Statistics", level: "Graduate",
                    summary: "The lasso and its relatives: generalized linear models, group and fused penalties, optimization algorithms, sparse multivariate methods and theory.",
                    pdf: URL(string: "https://drive.google.com/uc?export=download&id=1-9MWBSfViiymncPD60bCDTAicai3o2W8")!, homepage: URL(string: "https://hastie.su.domains/StatLearnSparsity/")!,
                    license: "Free PDF for personal use, with the publisher's permission (CRC Press)", bytes: 10537333),
    ]

    public static var subjects: [String] { Array(Set(books.map(\.subject))).sorted() }

    /// Books matching words of a query in their title, authors, subject or summary.
    public static func search(_ query: String) -> [CatalogBook] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return books }
        return books.filter { book in
            let text = ([book.title, book.subtitle ?? "", book.subject, book.summary] + book.authors).joined(separator: " ").lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
            return words.allSatisfy { text.contains($0.folding(options: .diacriticInsensitive, locale: nil)) }
        }
    }
}
