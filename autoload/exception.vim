" Definition of a stack trace:
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

" To test the exception#trace() function, install the following `cd` mapping
" and the `FuncA()`, `FuncB()`, `FuncC()` functions:
"
"         nno cd :call FuncA()<cr>
"
"         fu! FuncA() abort
"             call FuncB()
"         endfu
"
"         fu! FuncB() abort
"             call FuncC()
"         endfu
"
"         fu! FuncC() abort
"             abcd
"         endfu
"
" Then, press `cd`, and execute `:WTF`.

fu! exception#trace() abort
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

    let [ i, e, errors ] = [ 0, 0, [] ]
"         │  │  │
"         │  │  └─ list of errors built in the next while loop
"         │  └─ index of the last line where an error occurred
"         └─ index of the line of the log currently processed in the next
"            while loop

    " iterate over the lines in the log
    while i < len(lines)

        " if a line begins with “Error detected while processing function“
        " and the previous one with “line 123“ (123 being a random number)
        if i > 1 && lines[i] =~# '^Error detected while processing function '
                    \ && lines[i-1] =~? '\v^line\s+\d+'

            " get the line where the error occurred
            let lnum  = matchstr(lines[i-1], '\d\+')

"               ┌─ typical value:    <SNR>3_broken_func[123]
"               │
            let stack = printf('%s[%d]', lines[i][41:-2], lnum)
"                                        │
"                                        └─ name of the function
"                                           the name begins after the 41th character,
"                                           and `-2` gets rid of a colon at the end of the line
            call add(errors, {
                             \  'stack': reverse(split(stack, '\.\.')),
                             \  'msg':   lines[i-2],
                             \ })
            let e = i
        endif

        " increment `i` to process next line in the log, in the next
        " iteration of the while loop
        let i += 1

"          ┌─ there has been at least an error
"          │
        if e && i - e > 3
"               └───────┤
"                       └ there're more than 3 lines between the current line of the
"                         log, and the last one which contained a “Error detected
"                         while processing function“ message

            " get out of the while loop because we're only interested in the last error
            break

            " If we're only interested in the last error, then why 3? :
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
            "         line    12:                                     │ distance < 3 lines
            "         E492: Not an editor command:     bar            │            │
            "         Error detected while processing function baz   <+            └ that's where the 3,
            "         line    34:                                                    in the `i - e > 3` condition,
            "         E492: Not an editor command:     qux                           comes from
        endif
    endwhile

    " if there aren't any error, return
    if empty(errors)
        return
    endif

    let errlist = []

    let g:stack  = deepcopy(stack)
    let g:errors = deepcopy(errors)
    for err in errors

"                                      ┌ number of digits in the length of the stack trace
"                                      │
"                                      │ for example, if the stack trace tracks
"                                      │ a sequence of 12 nested functions
"                                      │ then `len(len(err.stack))` is 2,
"                                      │ because there are 2 digits in 12
"                                      │
"                    ┌─────────────────┤
        let digits = len(len(err.stack))
"                        └────────────┤
"                                     └ length of the error stack
"
"                                       for example, if the error occurred in line 56 of `FuncC`,
"                                       which called in line 34 of `FuncB`,
"                                       which was called in line 12 of `FuncA`,
"                                       then `err.stack` is the list:
"
"                                               [ 'FuncA[12]', 'FuncB[34]', 'FuncC[56]' ]

        " To understand the `type` key, read :h errorformat-multi-line
        "
        " FIXME:
        " Apparently, it tells Vim what's the type of an error (for example,
        " W for Warning). And according to this thread:
        "         https://stackoverflow.com/q/4403824
        "
        " … it should have an influence on the `%t` item if used in 'errorformat'.
        " But atm, it doesn't make any difference on my system.
        " Besides, after the line number of an error, the keyword (type?)
        " `info` is always written, no matter which value I give to the key
        " `type` (tested with various &efm values given in the previous
        " stackoverflow thread).
        let i = 0
        call add(errlist, {
                          \   'text':  err.msg,
                          \   'lnum':  0,
                          \   'bufnr': 0,
                          \   'type':  'E',
                          \ })

        for t in err.stack
            let func = matchstr(t, '\v.{-}\ze\[\d+\]$')
            let lnum = str2nr(matchstr(t, '\v\[\zs\d+\ze\]$'))

            let verb = split(execute('sil! verbose function '.func), "\n")
            if len(verb) < 2
                continue
            endif

            let src = fnamemodify(matchstr(verb[1], '\vLast set from \zs.+'), ':p')
            if !filereadable(src)
                continue
            endif

            let pat = '\v\C^\s*fu%[nction]!?\s+'
            if func =~# '^<SNR>'
                let pat .= '%(\<%(sid|SID)\>|s:)'
                let func = matchstr(func, '\v\<SNR\>\d+_\zs.+')
            endif
            let pat .= func.'>'

            for line in readfile(src)
                let lnum += 1
                if line =~# pat
                    break
                endif
            endfor

            if !empty(src) && !empty(func)
                let fname = fnamemodify(src, ':.')
                call add(errlist, {
                                  \   'text':     printf('%*s. %s', digits, '#'.i, t),
                                  \   'filename': fname,
                                  \   'lnum':     lnum,
                                  \   'type':     'I',
                                  \ })
            endif

            let i += 1
        endfor
    endfor

    if !empty(errlist)
        call setqflist(errlist, 'r')
        copen
    endif
endfu
