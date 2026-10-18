# MiM CoreAI vision runtime

The local package contains the language runtime from `john-rocky/coreai-models`
0.2.8-zoo and the vision geometry, preprocessing and graph helpers from
`john-rocky/coreai-kit` 0.7.3. Exact revisions and original file hashes are in
`UPSTREAM.json`. The respective BSD licenses and attribution notices are included.

CoreAI declarations are conditionally excluded on Simulator, whose SDK has no
CoreAI framework. The app uses AFM there. Device inference uses the same pipelined
engine and LFM image preprocessing as the separately tested CoreAIKit probe.
`VisionSceneModel` adds a single-image, greedy response path; no remote download,
account, model catalog or conversation UI is included in this package.
