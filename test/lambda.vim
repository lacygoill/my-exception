vim9script

def Func()
    timer_start(0, () => execute('invalid'))
enddef
#}}}
Func()
