# Finishing the work

- At the end of every piece of work on the project, before the final reply, quit Cascade and relaunch it without asking for further confirmation.
- If you changed the app's code, finish the build first and relaunch the updated version only if the build succeeds.
- Check that the app actually started again. If something blocks the build or the relaunch, say so in the final reply.
- On every successful build, update `/Applications/Cascade.app` so that it points to the build just produced. The shared Xcode scheme and `scripts/build-development.sh` run `scripts/update-application-link.sh`; if you use another build command, run the same script on the resulting `.app` before the relaunch.
