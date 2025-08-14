# GDB script for debugging Cebolinha HTTP parsing
# Usage: gdb -x debug_http.gdb bin/server

# Setup for multi-threading
set follow-fork-mode parent
set detach-on-fork off
set non-stop off
set pagination off

# Break at key HTTP parsing points
break action

# Display helpful info when breakpoints hit
echo \n
echo =======================================\n
echo  Cebolinha HTTP Debug Session Started\n
echo =======================================\n
echo \n
echo When breakpoint hits:\n
echo   1. Check thread: info threads\n
echo   2. Lock scheduler: set scheduler-locking on\n
echo   3. Step through: stepi or nexti\n
echo   4. Examine buffer: x/200c request_buffer\n
echo   5. Check parsed data:\n
echo      - x/s verb_ptr (after loading address)\n
echo      - x/xg verb_len\n
echo      - x/s path_ptr (after loading address)\n
echo      - x/xg path_len\n
echo \n
echo Then run in another terminal:\n
echo   curl -X POST http://localhost:3000/api/test\n
echo   curl http://localhost:3000/\n
echo \n

# Start the server
run
