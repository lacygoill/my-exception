" Source:
" https://github.com/tweekmonster/exception.vim/blob/ca36f1ecf5b4cea1206355e8e5e858512018a5db/autoload/exception.vim

" Acronym used in the comments:
"     TV = Typical Value
"          example used to illustrate which kind of value a variable could store

" Definition of a stack trace: "{{{
"
" Programmers  commonly use  stack  tracing during  interactive and  post-mortem
" debugging.  End-users may  see a  stack trace  displayed as  part of  an error
" message, which the user can then report to a programmer.
"
" A stack trace allows tracking the sequence  of nested functions called - up to
" the point where  the stack trace is generated. In  a post-mortem scenario this
" extends up to the function where the failure occurred (but was not necessarily
" caused).
"
" For more info:
"         https://en.wikipedia.org/wiki/Stack_trace
""}}}
" To test the stacktrace#qfl() function, install the following `cd` mapping "{{{
" and the `FuncA()`, `FuncB()`, `FuncC()`, `FuncD()` functions:
"
"        nno cd :call FuncA()<cr>
"
"        fu! FuncA()
"            call FuncB()
"            call FuncC()
"        endfu
"
"        fu! FuncB()
"            abcd
"        endfu
"
"        fu! FuncC()
"            call s:FuncD()
"        endfu
"
"        fu! s:FuncD()
"            efgh
"        endfu
"
" Then, press `cd`, and execute `:WTF`.
"
""}}}
" stacktrace#qfl "{{{

fu! stacktrace#qfl(...) abort

    " TV for `errors`:
    "         [
    "         \   {'stack': ['<SNR>3_FuncC[56]', 'FuncB[34]', 'FuncA[12]'],
    "         \   'msg' :   'E492: Not an editor command:     abcd'},
    "         \
    "         \   {'stack': ['<SNR>3_FuncF[99]', 'FuncE[90]', 'FuncD[78]'],
    "         \   'msg' :   'E492: Not an editor command:     efgh'},
    "         ]
    "
    " In this fictitious example, 2 errors occurred in s:FuncC() and s:FuncF(),
    " and the chains of calls were:
    "         FuncA → FuncB → s:FuncC
    "         FuncD → FuncE → s:FuncF
    let l:errors = s:get_raw_trace(get(a:000, 0, 3))

    " if there aren't any error, return
    if empty(l:errors)
        return
    endif

    " initialize the qfl
    let qfl = []

    " iterate over the errors (there could be only one)
    for err in l:errors
        "                              ┌ number of digits in the length of the stack trace
        "                              │ we'll need this number to format an expression
        "                              │ in a `printf()` later
        "                              │
        "                              │ for example, if the stack trace tracks
        "                              │ a sequence of 12 nested functions
        "                              │ then `len(len(err.stack))` is 2,
        "                              │ because there are 2 digits in 12
        "                              │
        "            ┌─────────────────┤
        let digits = len(len(err.stack))
        "                └────────────┤
        "                             └ length of the error stack
        "
        "                               for example, if the error occurred in line 56 of `FuncC`,
        "                               which was called in line 34 of `FuncB`,
        "                               which was called in line 12 of `FuncA`,
        "                               then `err.stack` is the list:
        "
        "                                       [ 'FuncA[12]', 'FuncB[34]', 'FuncC[56]' ]

        " we use `i` to index the position of a function call in the stack trace
        let i = 0

        " add the error message to the qfl
        call add(qfl, {
                      \   'text':  err.msg,
                      \   'lnum':  0,
                      \   'bufnr': 0,
                      \ })

        " Now, we need to add to the qfl the function calls which lead to the error.
        " And for each of them, we need to find out where it was made:
        "
        "         - which file
        "         - which line of the file (!= line of the function)
        "
        " TV for `err.stack`:    [ 'FuncB[34]', 'FuncA[12]' ]
        " TV for `func_call`:      'FuncB[34]'
        for func_call in err.stack
            " TV: 'FuncB'
            let func_name = matchstr(func_call, '\v.{-}\ze\[\d+\]$')

            " if we don't have a function name, process next function call in
            " the stack
            if empty(func_name)
                continue
            endif

            " TV: '34'
            let l:lnum = str2nr(matchstr(func_call, '\v\[\zs\d+\ze\]$'))

            " TV:
            " ['   function FuncB()', '    Last set from ~/.vim/vimrc', …, '34    abcd', …, '   endfunction']
            let func_def = split(execute('sil! verbose function '.func_name), "\n")

            " if the function definition is shorter than 2 lines, the
            " information we need isn't there, so don't bother creating an
            " entry in the qfl for it; instead process next function call
            " in the stack
            if len(func_def) < 2
                continue
            endif

            " expand the full path of the source file from which the function
            " call was made
            let src = fnamemodify(matchstr(func_def[1], '\vLast set from \zs.+'), ':p')
            " if it's not readable, we won't be able to visit it from the qfl,
            " so, again, process next function call in the stack
            if !filereadable(src)
                continue
            endif

            " build a pattern to match a line beginning with:
            "     function! FuncA
            " … or
            "     function! s:FuncA
            " … or
            "     function! <sid>FuncA

            " 1st part of the pattern (before the name of the function)
            let pat = '\v\C^\s*fu%[nction]!?\s+'

            " if the function is script-local, we can't add the raw function
            " name (with `<SNR>`), because that's not how it was written in the
            " source file
            if func_name =~# '^<SNR>'
                " add the 3 possible script-local prefix that the author of
                " the plugin could have used:    `s:`, `<sid>`, `<SID>`
                let pat       .= '%(\<%(sid|SID)\>|s:)'
                " get the name of the function without `<SNR>3_`
                let func_name  = matchstr(func_name, '\v\<SNR\>\d+_\zs.+')
            endif
            " add the name of the function
            let pat .= func_name.'>'

            " the function call was made on some line of the source file
            " find which one
            for line in readfile(src)
                let l:lnum += 1
                if line =~# pat
                    break
                endif
            endfor

            " Finally, we can add an entry for the function call.
            " We have its filename with `src`.
            " We have its line address with `l:lnum`.
            " And we can generate a simple text with:
            "
            "                  ┌─ width of the digits
            "                  │
            "         printf('%*s. %s', digits, '#'.i, func_call),
            "                 │    │
            "                 │    └─ function call; ex: 'FuncA[12]'
            "                 └─ index of the function call in the stack
            "
            " The final text could be sth like:
            "         '0. Func[12]'

            call add(qfl, {
                          \   'text':     printf('%*s. %s', digits, '#'.i, func_call),
                          \   'filename': src,
                          \   'lnum':     l:lnum,
                          \   'type':     'I',
                          \ })

                          " To understand the `type` key, read :h errorformat-multi-line, and:
                          "         https://stackoverflow.com/q/4403824
                          "
                          " Apparently, it tells Vim what's the type of an error.
                          " By default, the type should be displayed after the line number of an
                          " entry in the qfl. Use E for Error, W for Warning, and I for Info.
                          "
                          " Technically, it probably has an influence on the `%t` item used in
                          " 'errorformat'.

            " increment `i` to update the index of the next function call in
            " the stack
            let i += 1
        endfor
    endfor

    " populate the qfl
    if !empty(qfl)
        call setqflist(qfl)
        copen
    endif
endfu

"}}}
" get_raw_trace "{{{

fu! s:get_raw_trace(...) abort
    let max_dist = get(a:000, 0, 3)

    " get the log messages
    let lines = reverse(split(execute('sil messages'), "\n"))
    "               │
    "               └─ reverse the order because we're interested in the most
    "                  recent error

    " if we've just started Vim, there'll be only 2 lines in the log
    " in this case don't do anything, because there's no error
    if len(lines) < 3
        return
    endif

"         ┌─ index of the line of the log currently processed in the next while loop
"         │  ┌─ index of the last line in the log where an error occurred
"         │  │
    let [ i, e, l:errors ] = [ 0, 0, [] ]
"               │
"               │  list of errors built in the next while loop
"               │  each error will be a dictionary containing 2 keys,
"               └─  a stack trace and a message

    " iterate over the lines in the log
    while i < len(lines)

        " if a line begins with “Error detected while processing function“
        " and the previous one with “line 123“ (123 being a random number)
        if i > 1 && lines[i] =~# '^Error detected while processing function '
                    \ && lines[i-1] =~? '\v^line\s+\d+'

            " … then get the line where the error occurred
            " we need it to complete the stack (in the next `printf()`)
            let l:lnum  = matchstr(lines[i-1], '\d\+')

            " … and the name of the innermost function where an error occurred
            let inner_func = lines[i][41:-2]
            "                         │  │
            "                         │  └─ get rid of a colon at the end of the line
            "                         └─ the name begins after the 41th character

            " TV for `stack`:    function FuncA[12]..FuncB[34]..FuncC[56]:
            let stack = printf('%s[%d]', inner_func, l:lnum)
            "                     └──┤
            "                        └ add the address of the line where the
            "                          innermost error occurred (ex: 56),
            "                          inside square brackets (to follow the
            "                          notation used by Vim for the outer functions)

            " Now that we have generated a primitive stack, we split it into
            " a list (useful for further processing), we enrich it with
            " the associated error message associated, and add the resulting
            " dictionary to the `errors` list.
            " TV for the `stack` variable: "{{{
            "         FuncA[1]..FuncB[1]..FuncC[1]
            "
            " TV for the `stack` key:
            "         [ 'FuncA[12]', 'FuncB[34]', 'FuncC[56]' ]
            "
            " TV for the `msg` key:
            "         E492: Not an editor command:     abcd
            "
            " Since, the messages in the log have been reversed:
            "         lines[i]   = error
            "         lines[i-1] = address of the error
            "         lines[i-2] = message of the error
            ""}}}
            call add(l:errors, {
                               \  'stack': reverse(split(stack, '\.\.')),
                               \  'msg':   lines[i-2],
                               \ })

            " remember the index of the line of the log where an error occurred
            let e = i
        endif

        " increment `i` to process next line in the log, in the next iteration
        " of the while loop
        let i += 1

        "  ┌─ there has been at least an error
        "  │
        if e && i - e > max_dist
        "       └───────┤
        "               └ there're more than `max_dist` lines between the current
        "                 line of the log, and the last one which contained a
        "                 “Error detected while processing function“ message

            " get out of the while loop because we're only interested in the last error
            break

            " If we're only interested in the last error, then why 3? : "{{{
            "         i - e > 3
            "
            " Why not 1? :
            "         i - e > 1
            "
            " Because an error takes 3 lines in the log. Example:
            "
            "         Error detected while processing function foo
            "         line    12:
            "         E492: Not an editor command:     bar
            "
            " Note that if we have several consecutive errors, the while loop
            " should still process them all, because there will only be
            " 2 lines between 2 of them. Example:
            "
            "         Error detected while processing function foo   <+
            "         line    12:                                     │ max_dist
            "         E492: Not an editor command:     bar            │
            "         Error detected while processing function baz   <+
            "         line    34:
            "         E492: Not an editor command:     qux
            ""}}}
        endif
    endwhile

    return l:errors
endfu

"}}}
