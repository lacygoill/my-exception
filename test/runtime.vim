vim9script

def FuncA()
    FuncB()
enddef

def FuncB()
    # error
    eval [][0]
enddef

FuncA()

