if exists('g:loaded_stacktrace')
    finish
endif
let g:loaded_stacktrace = 1

" Usage:
"
"     :WTF 5
"
" Populate qfl with the  last error, as well as the previous  errors, as long as
" they are less than 5 lines away from each other in the message log.

com -bar -nargs=? WTF call stacktrace#main(<q-args> != '' ? <q-args> : 3)

nno <silent><unique> !w :<c-u>call stacktrace#main(v:count ? v:count : 3)<cr>
nno <silent><unique> !W :<c-u>call stacktrace#main(1000)<cr>
