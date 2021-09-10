@echo off
echo -----------------------------------------
echo *** Execute Best Practices Analyzer***
echo -----------------------------------------
REM: Stripping out double quotes to run tabular editor correctly.
set "bpa=%~1"
set "bpa=%bpa:""="%"
%bpa%