@echo off
rem SPDX-License-Identifier: Apache-2.0
rem The astraOS SDK command line on Windows (needs Python 3).
where py >nul 2>nul && (py -3 "%~dp0astra" %* & exit /b %errorlevel%)
python "%~dp0astra" %*
