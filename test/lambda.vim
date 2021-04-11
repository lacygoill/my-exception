vim9script

def Func()
    timer_start(0, (_) => execute('invalid'))
enddef
#}}}
Func()
