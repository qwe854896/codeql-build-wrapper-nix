/**
 * @name Database Statistics
 * @description Summary statistics to verify the CodeQL database is valid.
 *              Shows counts of various code elements.
 * @kind table
 * @id cpp/database-stats
 * @tags verification
 */

import cpp

// Count functions
int countFunctions() {
    result = count(Function f | f.fromSource())
}

// Count files
int countFiles() {
    result = count(File f | exists(Function fn | fn.fromSource() and fn.getFile() = f))
}

// Count parameters
int countParameters() {
    result = count(Parameter p | p.getFunction().fromSource())
}

// Count local variables
int countLocalVariables() {
    result = count(LocalVariable v | v.getFunction().fromSource())
}

// Count function calls
int countCalls() {
    result = count(FunctionCall c | c.getEnclosingFunction().fromSource())
}

from string metric, int value
where
    (metric = "Functions" and value = countFunctions()) or
    (metric = "Source Files" and value = countFiles()) or
    (metric = "Parameters" and value = countParameters()) or
    (metric = "Local Variables" and value = countLocalVariables()) or
    (metric = "Function Calls" and value = countCalls())
select metric, value
order by metric
