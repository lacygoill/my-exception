" Source:
" https://github.com/tweekmonster/exception.vim/blob/ca36f1ecf5b4cea1206355e8e5e858512018a5db/autoload/exception.vim

" Acronym used in the comments:
"     TV = Typical Value
"          example used to illustrate which kind of value a variable could store

" Definition of a stack trace: {{{1
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

" Test {{{1
"
" To test the stacktrace#qfl() function, install the following `cd` mapping
" and the `FuncA()`, `FuncB()`, `FuncC()`, `FuncD()` functions:

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

" Then, press `cd`, and execute `:WTF`.

fu! s:build_qfl(errors) abort "{{{1
    let qfl = []

    " iterate over the errors (there could be only one)
    for err in a:errors
        " we use `i` to index the position of a function call in the stack trace
        let i = 0

        " add the error message to the qfl
        call add(qfl, {
                    \   'text':  err.msg,
                    \   'lnum':  0,
                    \   'bufnr': 0,
                    \ })

        " Now, we need to add to the qfl, the function calls which lead to the error.
        " And for each of them, we need to find out where it was made:
        "
        "         - which file
        "         - which line of the file (!= line of the function)
        "
        " TV for `err.stack`:    ['FuncB[34]', 'FuncA[12]']
        " TV for `call`:          'FuncB[34]'
        for call in err.stack
            " TV: 'FuncB'
            let name = matchstr(call, '\v.{-}\ze\[\d+\]$')

            " if we don't have a function name, process next function call in
            " the stack
            if empty(name)
                continue
            endif

            " TV: '34'
            let lnum = str2nr(matchstr(call, '\v\[\zs\d+\ze\]$'))

            " if the name of a function contains a slash, or a dot, it's
            " not a function, it's a file
            "
            " it happens when the error occurred in a sourced file, like
            " a ftplugin; put a garbage command in one of them to reproduce
            if name =~# '[/.]'
                call add(qfl, {
                            \   'text':     '',
                            \   'filename': name,
                            \   'lnum':     lnum,
                            \ })
                " there's no chain of calls, the only error comes from this file
                continue
            else
                " TV:
                "     ['   function FuncB()',
                "    \ '    Last set from ~/.vim/vimrc',
                "    \ …,
                "    \ '34    abcd',
                "    \ …,
                "    \ '   endfunction']
                let def = split(execute('verb function '.name, 'silent!'), '\n')
            endif

            " if the function definition doesn't have at least 2 lines, the
            " information we need isn't there, so don't bother creating an
            " entry in the qfl for it; instead process next function call
            " in the stack
            if len(def) < 2
                continue
            endif

            " expand the full path of the source file from which the function
            " call was made
            let src = fnamemodify(matchstr(def[1], '\vLast set from \zs.+\ze line \d+'), ':p')
            " if it's not readable, we won't be able to visit it from the qfl,
            " so, again, process next function call in the stack
            if !filereadable(src)
                continue
            endif
            let lnum += matchstr(def[1], '\vLast set from .+ line \zs\d+')

            " Finally, we can add an entry for the function call.
            " We have its filename with `src`.
            " We have its line address with `lnum`.
            " And we can generate a simple text with:
            "
            "         printf('%s. %s', i, call),
            "                 │   │
            "                 │   └─ function call; ex: 'FuncA[12]'
            "                 └─ index of the function call in the stack
            "                    the lower, the deeper
            "
            " The final text could be sth like:
            "         '0. Func[12]'

            call add(qfl, {
                        \   'text':     printf('%s. %s', i, call),
                        \   'filename': src,
                        \   'lnum':     lnum,
                        \ })

            " increment `i` to update the index of the next function call in
            " the stack
            let i += 1
        endfor
    endfor

    return qfl
endfu

fu! s:get_raw_trace(...) abort "{{{1
    let max_dist = get(a:000, 0, 3)

    " get the log messages
    "
    " for some reason, `execute()` sometimes produces  ┐
    " 1 or several consecutive empty line(s)           │
    " even though they aren't there in the output of   │
    " `:messages`                                      │
    let msgs = reverse(split(execute('messages'), '\n\+'))
    "          │
    "          └─ reverse the order because we're interested in the most
    "             recent error

    " if we've just started Vim, there can't be any error, so don't do anything
    if len(msgs) < 3
        return
    endif

    "    ┌ index of the message processed in the next loop
    "    │
    "    │  ┌ index of the last message where an error occurred
    "    │  │
    let [i, e, l:errors] = [0, 0, []]
    "           │
    "           └ list of errors built in the next loop;
    "             each error will be a dictionary containing 2 keys,
    "             whose values will be a stack and a message

    " iterate over the messages in the log
    while i < len(msgs)

        " if a message begins with “Error detected while processing “
        " and the previous one with “line {some_number}“
        if i > 1 && msgs[i]   =~# '^Error detected while processing '
        \        && msgs[i-1] =~? '\v^line\s+\d+'

            " … then get the line address in the innermost function where the
            " error occurred
            let lnum = matchstr(msgs[i-1], '\d\+')

            " … and the stack of function calls leading to the error
            let partial_stack = matchstr(msgs[i], '\vError detected while processing %(function )?\zs.*\ze:$')

            " combine `lnum` and `partial_stack` to build a string describing
            " the complete stack
            let stack = printf('%s[%d]', partial_stack, lnum)
            "                     └──┤
            "                        └ add the address of the line where the
            "                          innermost error occurred (ex: 56),
            "                          inside square brackets (to follow the
            "                          notation used by Vim for the outer functions)
            "
            " TV for `stack`:    function FuncA[12]..FuncB[34]..FuncC[56]

            " Now that we have the stack as a string, we need to:
            "
            "       1. convert it into a list
            "       2. store it into a dictionary
            "       3. add the associated error message to the dictionary
            "       4. add the dictionary to a list of all errors found so far

            " TV for the `stack` key: {{{
            "         ['FuncA[12]', 'FuncB[34]', 'FuncC[56]']
            "
            " TV for the `msg` key:
            "         E492: Not an editor command:     abcd
            "
            " Since, the messages in the log have been reversed:
            "         msgs[i-2] = E123: …
            "         msgs[i-1] = line  42:
            "         msgs[i]   = Error detected while processing …:
            ""}}}
            call add(l:errors, {
                             \   'stack': reverse(split(stack, '\.\.')),
                             \   'msg':   msgs[i-2],
                             \ })

            " remember the index of the message in the log where an error occurred
            let e = i
        endif

        " in the next iteration of the loop, process next message
        let i += 1

        "  ┌─ there has been at least an error
        "  │
        if e && i - e > max_dist
        "       └───────┤
        "               └ there're more than `max_dist` lines between the next
        "                 message in the log, and the last one which contained
        "                 “Error detected while processing function“

            " get out of the loop because the distance is too high
            break

            " If we're only interested in the last error, then why 3? : {{{
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
            " Note that if we have several consecutive errors, the loop
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

fu! stacktrace#main(lvl) abort "{{{1
    " TV for `errors`:{{{
    "         [
    "         \ {'stack': ['FuncB[34]', 'FuncA[12]'],
    "         \  'msg' : 'E492: Not an editor command:     abcd'},
    "         \
    "         \ {'stack': ['<SNR>3_FuncD[78]', 'FuncC[56]'],
    "         \  'msg' : 'E492: Not an editor command:     efgh'},
    "         ]
    "
    " In this fictitious example, 2 errors occurred in FuncB() and s:FuncD(),
    " and the chains of calls were:
    "         FuncA → FuncB
    "         FuncC → s:FuncD
    "}}}
    let l:errors = s:get_raw_trace(a:lvl)

    if empty(l:errors)
        echo '[stacktrace] no stack trace in :messages'
        return
    endif

    let qfl = s:build_qfl(l:errors)
    if empty(qfl)
        echohl ErrorMsg
        echo '[stacktrace] unable to parse the stack trace'
        echohl NONE
        return
    endif

    call s:populate_qfl(qfl)
endfu

fu! s:populate_qfl(qfl) abort "{{{1
    call setqflist(a:qfl)
    call setqflist([], 'a', { 'title': 'WTF' })
    do <nomodeline> QuickFixCmdPost copen
    call qf#set_matches('stacktrace:populate_qfl', 'Conceal', 'double_bar')
    call qf#create_matches()
endfu
