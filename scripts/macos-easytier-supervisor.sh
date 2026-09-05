#!/bin/bash
# Invoked with a fixed script and an argv array, never interpolated shell input.
# stdin is a lifetime pipe owned by the GUI. EOF also handles a GUI crash, even
# after sudo's authorization timestamp has expired. Only our child is stopped.
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
"$@" </dev/null &
child=$!

cleanup() {
  if kill -0 "$child" 2>/dev/null; then
    kill -TERM "$child" 2>/dev/null || true
    for ((attempt = 0; attempt < 30; attempt++)); do
      kill -0 "$child" 2>/dev/null || break
      /bin/sleep 0.1
    done
    kill -KILL "$child" 2>/dev/null || true
  fi
  wait "$child" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

while kill -0 "$child" 2>/dev/null; do
  if IFS= read -r -t 1 _control; then
    break
  else
    read_status=$?
    # Bash returns >128 for a read timeout, 1 for EOF.
    ((read_status > 128)) || break
  fi
done

# Preserve an early EasyTier failure so the GUI can explain the real exit code.
if ! kill -0 "$child" 2>/dev/null; then
  wait "$child"
  exit "$?"
fi
