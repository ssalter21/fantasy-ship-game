Type: grilling
Status: open

## Question

How does the simulation core stay decoupled from presentation, so the exact same run can execute headless (no UI, for tests/simulation) or with a UI (for a human to play)? Pin down: what the boundary/interface between "core sim" and "presentation" looks like, how a UI-driven session and a headless-driven session both drive that boundary, and what that implies for the engine's core loop structure in Odin.
