" Usage:
"
" :WTF 5  →    populate qfl with the last error, as well as the previous
"              errors, as long as they are less than 5 lines away from each
"              other in the message log

com! -nargs=? WTF call stacktrace#qfl(<args>)
"           │
"           └─ 3 is used by default
