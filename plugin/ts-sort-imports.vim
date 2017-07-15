if exists("g:ts_sort_imports_loaded") || &cp | finish | endif
let g:ts_sort_imports_loaded = 1
let s:keepcpo = &cpo
set cpo&vim

augroup tssortimports
  autocmd!
  au BufRead *.ts command! FixImports call <SID>TsSortImports()
augroup END

function! s:SortCommaList(list) abort
    let l:words = split(a:list, ',')
    for i in range(0, len(l:words) - 1)
        let l:words[i] = substitute(l:words[i], '\s*', '', 'g')
    endfor
    return join(sort(l:words), ', ')
endfunction

function! s:TsSortImports() abort
    " Expected format for import parts:
    "     import { foo } from 'foo';
    let l:import_parts_re = '\([^{]*\){\([^}]\+\)}\(.*$\)'

    " this will only work if first line is blank
    call append(0, '')

    " makes lines like:
    "     import {
    "         foo
    "     } from 'foo';
    " into:
    "     import { foo } from 'foo';
    call cursor(1, 1)
    " need to do something for first line... if in position (1,1), the search won't match the import on that line
    let [l:start, l:end] = [search('^import'), search('}')]
    while l:start
        call cursor(l:start, 1)

        if l:start != l:end
            let l:line = join(getline(l:start, l:end))
            if !empty(l:line)
                exec l:start . ',' . l:end . 'delete'
                call append(l:start - 1, l:line)
            endif
        endif

        " begin sorting the items within the braces: { a, b, c }
        call cursor(l:start, 1)
        if getline('.') =~ '{[^}]*}'
            let l:line = substitute(getline('.'), l:import_parts_re, '\2', '')
            let l:sorted = substitute(getline('.'), '{ *[^}]* *}', '{ ' . <SID>SortCommaList(l:line) . ' }', '')
            exec l:start . ',' . l:start . 'delete'
            call append(l:start - 1, l:sorted)
        endif

        call cursor(l:start, 1)
        silent! s/ \+/ /g

        let [l:start, l:end] = [search('^import'), search('}')]
    endwhile

    " sort and replace imports that were previously joined to one line
    let [l:start, l:end] = [1, 1]
    call cursor(l:start, 1)
    while l:start < line('$')
        let [l:start, l:end] = [search('^import'), search('^\($\|\(import\)\@!.\)') - 1]

        " stop when import search does not return result
        if !l:start | break | endif

        let l:sorted = sort(getline(l:start, l:end))
        if !empty(l:sorted)
            exec l:start . ',' . l:end . 'delete'
            for line in l:sorted
                call append(l:start - 1, line)
                let l:start += 1
            endfor
        endif

        let l:start = l:end + 1
    endwhile

    call cursor(1, 1)
    let [l:start, l:end] = [1, 1]
    while l:start
        " Procedure:
        " 1. Find line that contains import { ... }. Assumes well defined imports.
        " 2. If line is too long, break imports onto new line
        " 3. Break the comma separated import symbols onto new lines
        " 4. Replace existing import line with new line separated
        let l:start = search('import')
        let l:line = getline(l:start)
        if l:start && len(l:line) >= 120
            let l:lines = split(substitute(l:line, l:import_parts_re, '\1{\n\2\n}\3', ''), '\n')
            let l:imports = split(get(l:lines, 1, ''), ', *')

            call remove(l:lines, 1)
            for idx in reverse(range(0, len(l:imports) - 1))
                let l:new_line = substitute(l:imports[idx], '\s*', '', 'g')
                if idx == len(l:imports) - 1
                    call insert(l:lines, l:new_line, 1)
                else
                    call insert(l:lines, substitute(l:new_line, '$', ',', ''), 1)
                endif
            endfor

            " replace line with new import lines
            exec l:start . ',' . l:start . 'delete'
            for line in reverse(l:lines)
                call append(l:start - 1, line)
            endfor

            " fix indentation
            for ii in range(0, len(l:lines) - 1)
                call cursor(l:start + ii, 1)
                normal! ==
            endfor
        endif
    endwhile

    " delete the added first line
    exec '1,1delete'
endfunction

let &cpo = s:keepcpo
unlet s:keepcpo
