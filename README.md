# dpmi-intrude-poc
DPMI debugger intrusion proof-of-concept for Windows 386

Debugging DPMI applications under Windows 386 can be difficult. The conventional technique to allow a debugger to retain control across the protected-mode switch is to hook INT 2Fh (the DOS API multiplex). INT 2F/1687 (from real/v86 mode) returns a protected-mode switch entry point that a would-be DPMI client can execute a far call to in order to switch itself into protected-mode. Execution resumes at the instruction just after the far call, with CS, DS, ES, and SS registers replaced with protected-mode selectors aliasing their real-mode contents before the switch. 

The debugger's hook passes through handling for all API requests except for AX=1687h. For that one, it gets the DPMI server's true entry point, but instead hands off its own, allowing it to take control just before the switch to protected-mode (i.e. the debugger can do some initialization, call the server's entry point, then do some initialization in protected mode, hooking exception vectors and so forth, then start executing the debuggee). 

This technique does not function under some DPMI hosts, such as Windows 386 (i.e. enhanced-mode Windows 3.x/9x). Windows 386 handles INT 2F/1687 entirely in protected-mode (inside a Ring-0 VxD) without ever consulting the real-mode interrupt chain. The traditional response to this has been to have a debugger trace (i.e. single-step) through the real-mode initialization code, detect when the debuggee is about to execute the switch, and then intrude right there. However, that solution is clunky (it can be made slightly less clunky by having the debugger automatically trace through every instruction, regaining control between every instruction albeit with a huge speed penalty, similar to pre-386 debugger watchpoints).

A superior solution is to obtain the entry point returned by INT 2F/1687 and hook _that_. However, this isn't directly possible on Windows 9x, as the entry point usually points to an ARPL instruction found within the ROM BIOS. The solution for this is to use the 80386's hardware debug registers and set a processor execution breakpoint at the linear address of the protected-mode switch entry point. However, there is no way to do this from Virtual 8086 Mode, as that's a privileged operation, so the debugger needs to itself be a DPMI client (this alleviates the requirement of using INT 2F/1687 that a DPMI server already be resident, not that this was a problem on Windows 386 as DPMI services are always available). Once in protected-mode, it can then execute the following sequence of steps:
1.) Use INT31 to set a debug breakpoint on the protected-mode switch linear address
2.) Use INT31 to execute a real-mode procedure
3.) Real-mode procedure uses INT21/25 to hook INT01 (the debug trap) -- DPMI 0.9 exception handlers only apply to protected-mode exceptions
4.) Real-mode procedure uses DOS EXEC to start another DPMI client, which traps into our interrupt handler upon hitting the break point

Potential issues
I believe the ARPL instruction is used for other things. If I remember rightly, the same ARPL instruction is used for all (or at least most?) v86->ring 0 break points. For example, I believe IFSMGR's real-mode hook eventually executes an ARPL to call into the 32-bit filesystem to handle INT21 calls. As I recall, the way the same ARPL is "multiplexed" to provide multiple services takes advantage of the fact that there are 4096 combinations of segment:offset pairs to create the same linear address. 

The problem is that the 386 processor breakpoints are based on linear addresses, so this could invoke spuriously. We can probably get around this by checking that the trapping CS:IP is the same as the DPMI entry point. 
