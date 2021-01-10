vim9

# Regular errors:{{{
#
#     vim9
#     nno cd <cmd>call <sid>FuncA()<cr>
#
#     def FuncA()
#         FuncB()
#         FuncC()
#     enddef
#
#     def FuncB()
#         eval [][0]
#     enddef
#
#     def FuncC()
#         FuncD()
#     enddef
#
#     def FuncD()
#         invalid
#     enddef
#
# Press `cd`, and execute `:WTF`.
# You'll get a stacktrace for an error at compile time due to `:invalid`.
# If you fix it, you'll get another error at runtime due to `eval [][0]`.
#}}}
# Error in lambda:{{{
#
#     vim9
#     nno cd <cmd>call <sid>FuncA()<cr>
#
#     def FuncA()
#         timer_start(0, () => execute('invalid'))
#     enddef
#}}}
# Error in numbered function:{{{
#
#     let mydict = {'data': [0, 1, 2, 3]}
#     fu mydict.len()
#         invalid
#         return len(self.data)
#     endfu
#     echo mydict.len()
#}}}

