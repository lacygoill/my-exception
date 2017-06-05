fu! exception#trace() abort
    " get the log messages
    let lines = reverse(split(execute('sil messages'), "\n"))

    " if we've just started Vim, there'll be only 2 lines in the log
    " in this case don't do anything, because there's no error
    if len(lines) < 3
        return
    endif

    let i = 0
    let e = 0
    let errors = []

    while i < len(lines)
        if i > 1 && lines[i] =~# '^Error detected while processing function '
                    \ && lines[i-1] =~? '\v^line\s+\d+'
            let lnum = matchstr(lines[i-1], '\d\+')
            let stack = printf('%s[%d]', lines[i][41:-2], lnum)
            call add(errors, {
                             \  'stack': reverse(split(stack, '\.\.')),
                             \  'msg':   lines[i-2],
                             \ })
            let e = i
        endif

        let i += 1
        if e && i - e > 3
            break
        endif
    endwhile

    if empty(errors)
        return
    endif

    let errlist = []

    for err in errors
        let nw = len(len(err.stack))
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
                                  \   'text':     printf('%*s. %s', nw, '#'.i, t),
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
