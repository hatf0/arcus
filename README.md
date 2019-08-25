# Arcus
This is informally called "Arcus" (formerly beautiful-admin-panel). It is meant to be a competitor towards solutions such as Virtualizor, which have horrible UI/UX designs.

## Security
I have put my best effort into ensuring that this project is properly secure, however, if you notice any security issues, email me them, or create an issue in the repo.

## Compilation instructions
Run `build.sh`, or `dub build -c [api/web/orchestrator/vmm/cli]`.

This will generate a binary in the bin/ directory, which you will (probably) have to run with root privileges.

Running said binary assumes that you have the druntime/phobos standard library installed on your machine.

