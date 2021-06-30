vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Usage:
#
#     :WTF 5
#
# Populate qfl with the  last error, as well as the previous  errors, as long as
# they are less than 5 lines away from each other in the message log.

command -bar -nargs=? WTF stacktrace#main(<q-args> != '' ? <q-args> : 3)

nnoremap <unique> !w <Cmd>call stacktrace#main(v:count ? v:count : 3)<CR>
nnoremap <unique> !W <Cmd>call stacktrace#main(1000)<CR>
