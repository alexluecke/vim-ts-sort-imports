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
let s:import_start_re = '^\(\s*import\s*\)'
let s:import_names_re = '{ *\([^}]\+\) *}'
let s:import_end_re = ' *from *''\([^'']\+\)'';$'
let s:import_re = join([s:import_start_re, s:import_names_re, s:import_end_re], '')
let s:search_flags = 'W'

function! s:AlphaSortList(list) abort
    for i in range(0, len(a:list) - 1)
        " List can be formatted as:
        "     thing as thing2, otherThing
        " -> do not strip all whitespace
        let a:list[i] = substitute(a:list[i], '^\s*\(.\{-}\)\s*$', '\1', '')
        let a:list[i] = substitute(a:list[i], '\s\+', ' ', 'g')
    endfor
    return uniq(sort(a:list, 'i'))
endfunction

function! s:SortAndReplaceImportLines()
    let [l:start, l:end] = s:GetImportBlockStartEnd(1)

    while l:start && l:start < l:end
        let buckets = {}
        for line_number in range(l:start, l:end - 1)
            let path = substitute(getline(l:line_number), s:import_re, '\3', '')
            let imports = split(substitute(getline(l:line_number), s:import_re, '\2', ''), ',')
            let buckets[path] = has_key(buckets, path) ?  buckets[path] + imports : imports
        endfor

        exec l:start . ',' . (l:end - 1) . 'delete'

        for [path, imports] in items(buckets)
            call append(l:start - 1, s:BuildImportStatement(join(s:AlphaSortList(imports), ', '), path))
        endfor

        let [l:start, l:end] = s:GetImportBlockStartEnd(l:start + len(buckets) + 1)
    endwhile
endfunction

function! s:BuildImportStatement(imports, path)
    return 'import { ' . a:imports . ' } from ''' . a:path . ''';'
endfunction

function! s:GetImportStartEnd(start_row)
    let l:saved_pos = [line('.'), col('.')]
    let l:saved_line_count = line('$')
    call cursor(a:start_row, 1)
    let results = [search(s:import_start_re, 'Wnc'), search('; *$', 'Wnc')]
    call cursor(l:saved_pos[0] + (line('$') - l:saved_line_count), l:saved_pos[1])
    return results
endfunction

function! s:GetImportBlockStartEnd(start)
    let l:saved_pos = [line('.'), col('.')]
    let l:saved_line_count = line('$')
    call cursor(a:start, 1)
    let results = [search(s:import_start_re, 'Wnc'), search('^\($\|\(import\)\@!.\)', 'Wnc')]
    call cursor(l:saved_pos[0] + (line('$') - l:saved_line_count), l:saved_pos[1])
    return results
endfunction

function! s:JoinLines(start, end)
    if a:start < a:end
        let l:line = substitute(join(getline(a:start, a:end)), '^\s*', '', '')
        exec a:start . ',' . a:end . 'delete'
        call append(a:start - 1, l:line)
    elseif a:start == a:end
        call setline(a:start, substitute(getline(a:start), '^\s*', '', ''))
    endif
endfunction

" Makes lines like:
"     import {
"         foo
"     } from 'foo';
"     import {
"         bar
"     } from 'bar';
" into:
"     import { foo } from 'foo';
"     import { bar } from 'bar';
function! s:DoOneLinePerImport()
    let [l:start, l:end] = s:GetImportStartEnd(1)
    while l:start
        call s:JoinLines(l:start, l:end)
        let [l:start, l:end] = s:GetImportStartEnd(l:start + 1)
    endwhile
endfunction

" Sort and replace imports that were previously joined to one line. Blocks are groups of imports separated by a blank
" line
function! s:DoSortImportBlocks()
    let [l:start, l:end] = [1, 1]
    while l:start < line('$')
        call cursor(l:start, 1)
        let [l:start, l:end] = [search(s:import_start_re, s:search_flags), search('^\($\|\(import\)\@!.\)', s:search_flags) - 1]

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
        if l:start && len(l:line) >= &textwidth
            let l:lines = split(substitute(l:line, s:import_re, 'import {\n\2\n} from ''\3'';', ''), '\n')
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
    call s:SortAndReplaceImportLines()
    call s:DoSortImportBlocks()
    call s:DoFormatLongLineImports()
endfunction

function! s:ClearInitialWhitespace()
    while getline(1) =~ '^\s*$' && line('$') != 1
        exec '1,1delete'
    endwhile
endfunction

function! s:TsSortImports() abort
    let l:saved_pos = [line('.'), col('.')]
    let l:saved_line_count = line('$')

    silent! call s:ClearInitialWhitespace();
    silent! call s:SortImportsPipeline()

    call cursor(l:saved_pos[0] + (line('$') - l:saved_line_count), l:saved_pos[1])
    redraw!
endfunction

let &cpo = s:keepcpo
unlet s:keepcpo
