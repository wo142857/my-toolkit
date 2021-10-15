" 自动缩进时,缩进长度为4
set shiftwidth=4

" tab 显示宽度为4个空格
set tabstop=4

" 插入模式下，将tab字符替换为空格
set expandtab

" softtabstop的值为负数,会使用shiftwidth的值,两者保持一致,方便统一缩进.
set softtabstop=-1

" 搜索高亮
set hlsearch

" 自动调至上次退出时的光标位置
if has("autocmd")
  au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endif

" 设置文件编码
set encoding=utf-8 fileencodings=ucs-bom,utf-8,cp936
