/**
 * @name List All Functions
 * @description Lists all functions defined in source code with their locations.
 *              Use this to verify CodeQL database was built correctly.
 * @kind table
 * @id cpp/list-functions
 * @tags verification
 */

import cpp

from Function f, Location loc
where
    f.fromSource() and
    loc = f.getLocation()
select
    f.getName() as name,
    f.getType().toString() as returnType,
    f.getNumberOfParameters() as paramCount,
    loc.getFile().getRelativePath() as file,
    loc.getStartLine() as line,
    loc.getStartColumn() as col
order by file, line
