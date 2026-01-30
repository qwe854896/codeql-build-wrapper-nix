/**
 * @name Find Potentially Unsafe Functions
 * @description Finds calls to known unsafe C functions (strcpy, sprintf, etc.)
 *              that could lead to buffer overflows.
 * @kind problem
 * @problem.severity warning
 * @id cpp/unsafe-functions
 * @tags security
 *       verification
 */

import cpp

class UnsafeFunction extends Function {
    UnsafeFunction() {
        this.getName() in [
            "strcpy", "strcat", "sprintf", "vsprintf",
            "gets", "scanf", "sscanf", "fscanf",
            "strncpy", "strncat"  // These are "safer" but still problematic
        ]
    }
}

from FunctionCall call, UnsafeFunction target
where call.getTarget() = target
select call,
    "Call to potentially unsafe function '" + target.getName() + "' at " +
    call.getLocation().getFile().getRelativePath() + ":" +
    call.getLocation().getStartLine().toString()
