if exists("g:ts_sort_imports_loaded") || &cp | finish | endif
let g:ts_sort_imports_loaded = 1
let s:keepcpo = &cpo
set cpo&vim

augroup tssortimports
  autocmd!
  au BufRead *.ts command! TsSortImports call <SID>TsSortImports()
augroup END

" Expected format for import parts:
"     import { foo } from 'foo';
let s:import_parts_re = '\([^{]*\){\([^}]\+\)}\(.*$\)'
let s:search_flags = 'W'

function! s:SortCommaList(list) abort
    let l:words = split(a:list, ',')
    for i in range(0, len(l:words) - 1)
        " Imports can be formatted as:
        "     import { thing as thing2, otherThing } from './thing';
        " So do not string all whitespace since the import string will become:
        "     import { thingasthing2, otherThing }  from './thing';
        let l:words[i] = substitute(l:words[i], '\s*$', '', 'g')
        let l:words[i] = substitute(l:words[i], '^\s*', '', 'g')
        let l:words[i] = substitute(l:words[i], '\s\+', ' ', 'g')
    endfor
    return join(sort(l:words, 'i'), ', ')
endfunction

function s:GetSortedImportLine(line_pos)
    let l:line = substitute(getline(a:line_pos), s:import_parts_re, '\2', '')
    return substitute(getline(a:line_pos), '{ *[^}]* *}', '{ ' . <SID>SortCommaList(l:line) . ' }', '')
endfunction

function! s:SortAndReplaceImportLine(line_pos) abort
    " begin sorting the items within the braces: { a, b, c }
    if getline(a:line_pos) =~ '{[^}]*}'
        let l:sorted = s:GetSortedImportLine(a:line_pos)
        exec a:line_pos . ',' . a:line_pos . 'delete'
        call append(a:line_pos - 1, l:sorted)
    endif
endfunction

function! s:GetImportStartEnd(start_row)
    call cursor(a:start_row, 1)
    return [search('^import', s:search_flags), search('; *$', s:search_flags)]
endfunction

function! s:JoinLines(start, end)
    call cursor(a:start, 1)
    if a:start != a:end
        let l:line = join(getline(a:start, a:end))
        if !empty(l:line)
            exec a:start . ',' . a:end . 'delete'
            call append(a:start - 1, l:line)
        endif
    endif
endfunction

function! s:DoOneLinePerImport()
    " makes lines like:
    "     import {
    "         foo
    "     } from 'foo';
    "     import {
    "         bar
    "     } from 'bar';
    " into:
    "     import { foo } from 'foo';
    "     import { bar } from 'bar';
    let [l:start, l:end] = s:GetImportStartEnd(1)
    while l:start

        call s:JoinLines(l:start, l:end)
        call s:SortAndReplaceImportLine(l:start)

        silent! s/ \+/ /g

        let [l:start, l:end] = s:GetImportStartEnd(l:start)
    endwhile
endfunction

function! s:DoSortImportBlocks()
    " sort and replace imports that were previously joined to one line
    let [l:start, l:end] = [1, 1]
    while l:start < line('$')
        call cursor(l:start, 1)
        let [l:start, l:end] = [search('^import', s:search_flags), search('^\($\|\(import\)\@!.\)', s:search_flags) - 1]

        " stop when import search does not return result
        if !l:start | break | endif

        let l:sorted = sort(getline(l:start, l:end), 'i')
        if !empty(l:sorted)
            exec l:start . ',' . l:end . 'delete'
            for line in l:sorted
                call append(l:start - 1, line)
                let l:start += 1
            endfor
        endif

        let l:start = l:end + 1
    endwhile
endfunction

function! s:DoFormatLongLineImports()
    call cursor(1, 1)
    let [l:start, l:end] = [1, 1]
    while l:start
        " Procedure:
        " 1. Find line that contains import { ... }. Assumes well defined imports.
        " 2. If line is too long, break imports onto new line
        " 3. Break the comma separated import symbols onto new lines
        " 4. Replace existing import line with new line separated imports
        let l:start = search('^import', s:search_flags)
        let l:line = getline(l:start)
        if l:start && len(l:line) >= 120
            let l:lines = split(substitute(l:line, s:import_parts_re, '\1{\n\2\n}\3', ''), '\n')
            let l:imports = split(get(l:lines, 1, ''), ', *')

            call remove(l:lines, 1)
            for idx in reverse(range(0, len(l:imports) - 1))
                let l:new_line = substitute(l:imports[idx], '\s*', '', 'g')
                if !empty(l:new_line)
                    if idx == len(l:imports) - 1
                        call insert(l:lines, l:new_line, 1)
                    else
                        call insert(l:lines, substitute(l:new_line, '$', ',', ''), 1)
                    endif
                endif
            endfor

            " replace line with new import lines
            exec l:start . ',' . l:start . 'delete'
            for line in reverse(l:lines)
                call append(l:start - 1, line)
            endfor

            " fix indentation for added lines
            exec l:start . ',' . (l:start + len(l:lines) - 1) . 'normal! =='
        endif
    endwhile
endfunction

function! s:SortImportsPipeline()
    call s:DoOneLinePerImport()
    call s:DoSortImportBlocks()
    call s:DoFormatLongLineImports()
endfunction

function! s:TsSortImports() abort
    let l:saved_pos = [line('.'), col('.')]
    let l:saved_line_count = line('$')

    " this will only work if first line is blank
    call append(0, '')

    silent! call s:SortImportsPipeline()

    " delete the added first line
    exec '1,1delete'

    call cursor(l:saved_pos[0] + (line('$') - l:saved_line_count), l:saved_pos[1])
endfunction

let &cpo = s:keepcpo
unlet s:keepcpo
