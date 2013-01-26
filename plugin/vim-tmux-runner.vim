" TODO: maximize command
" TODO: open pane in other window, then copy in (avoid flickering during init)

function! s:InitVariable(var, value)
    if !exists(a:var)
        let escaped_value = substitute(a:value, "'", "''", "g")
        exec 'let ' . a:var . ' = ' . "'" . escaped_value . "'"
        return 1
    endif
    return 0
endfunction

function! s:OpenRunnerPane()
    let s:vim_pane = s:ActiveTmuxPaneNumber()
    let remote_cmd = join(["new-window", "-d", "-n", g:VtrDetachedName])
    call s:SendTmuxCommand(remote_cmd)
    let [s:detached_window, s:runner_pane] = [s:LastWindowNumber(), 0]
    if g:VtrGitCdUpOnOpen
        call s:GitCdUp()
    endif
    if g:VtrInitialCommand != ""
        call s:SendKeys(g:VtrInitialCommand)
    endif
    if g:VtrInitialCommand || g:VtrGitCdUpOnOpen
        call s:TimeoutWithProgess()
    endif
    call s:ReattachPane()
endfunction

function! s:TimeoutWithProgess()
    let timeout_portion = g:VtrInitTimeout / 3
    echohl String | echon 'Preparing runner.'
    for time in [1,2,3]
        execute join(['sleep', timeout_portion.'m'])
        echon '.'
    endfor
    echohl None
endfunction

function! s:DetachRunnerPane()
    if !s:RequireRunnerPane()
        return
    endif
    call s:BreakRunnerPaneToTempWindow()
    let cmd = join(["rename-window -t", s:detached_window, g:VtrDetachedName])
    call s:SendTmuxCommand(cmd)
endfunction

function! s:RequireRunnerPane()
    if !exists("s:runner_pane")
        echohl ErrorMsg | echom "VTR: No runner pane attached." | echohl None
        return 0
    endif
    return 1
endfunction

function! s:RequireDetachedPane()
    if !exists("s:detached_window")
        echohl ErrorMsg | echom "VTR: No detached runner pane." | echohl None
        return 0
    endif
    return 1
endfunction

function! s:RequireLocalPaneOrDetached()
    if !exists('s:detached_window') && !exists('s:runner_pane')
        echohl ErrorMsg | echom "VTR: No pane, local or detached." | echohl None
        return 0
    endif
    return 1
endfunction

function! s:KillLocalRunner()
    let targeted_cmd = s:TargetedTmuxCommand("kill-pane", s:runner_pane)
    call s:SendTmuxCommand(targeted_cmd)
    unlet s:runner_pane
endfunction

function! s:KillDetachedWindow()
    let cmd = join(["kill-window", '-t', s:detached_window])
    call s:SendTmuxCommand(cmd)
    unlet s:detached_window
endfunction

function! s:KillRunnerPane()
    if !s:RequireLocalPaneOrDetached()
        return
    endif
    if exists("s:runner_pane")
        call s:KillLocalRunner()
    else
        call s:KillDetachedWindow()
    endif
endfunction

function! s:ActiveTmuxPaneNumber()
    for pane_title in s:TmuxPanes()
        if pane_title =~ '\(active\)'
            return pane_title[0]
        endif
    endfor
endfunction

function! s:TmuxPanes()
    let panes = s:SendTmuxCommand("list-panes")
    return split(panes, '\n')
endfunction

function! s:FocusTmuxPane(pane_number)
    let targeted_cmd = s:TargetedTmuxCommand("select-pane", a:pane_number)
    call s:SendTmuxCommand(targeted_cmd)
endfunction

function! s:RunnerPaneDimensions()
    let panes = s:TmuxPanes()
    for pane in panes
        if pane =~ '^'.s:runner_pane
            let pattern = s:runner_pane.': [\(\d\+\)x\(\d\+\)\]'
            let pane_info =  matchlist(pane, pattern)
            return {'width': pane_info[1], 'height': pane_info[2]}
        endif
    endfor
endfunction

function! s:FocusRunnerPane()
    call s:EnsureRunnerPane()
    call s:FocusTmuxPane(s:runner_pane)
endfunction

function! s:SendTmuxCommand(command)
    let prefixed_command = "tmux " . a:command
    return system(prefixed_command)
endfunction

function! s:TargetedTmuxCommand(command, target_pane)
    if exists("s:detached_window")
        let target = ':'.s:detached_window.'.'.a:target_pane
    else
        let target = a:target_pane
    endif
    return join([a:command, " -t ", target])
endfunction

function! s:_SendKeys(keys)
    let targeted_cmd = s:TargetedTmuxCommand("send-keys", s:runner_pane)
    let full_command = join([targeted_cmd, a:keys])
    call s:SendTmuxCommand(full_command)
endfunction

function! s:SendKeys(keys)
    let cmd = g:VtrClearBeforeSend ? g:VtrClearSequence.a:keys : a:keys
    call s:_SendKeys(cmd)
    call s:SendEnterSequence()
endfunction

function! s:SendEnterSequence()
    call s:_SendKeys("Enter")
endfunction

function! s:SendClearSequence()
    if !s:RequireRunnerPane()
        return
    endif
    call s:_SendKeys(g:VtrClearSequence)
endfunction

function! s:GitCdUp()
    let git_repo_check = "git rev-parse --git-dir > /dev/null 2>&1"
    let cdup_cmd = "cd './'$(git rev-parse --show-cdup)"
    let cmd = shellescape(join([git_repo_check, '&&', cdup_cmd]))
    call s:SendKeys(cmd)
    call s:SendClearSequence()
endfunction

function! s:FocusVimPane()
    call s:FocusTmuxPane(s:vim_pane)
endfunction

function! s:LastWindowNumber()
    return split(s:SendTmuxCommand("list-windows"), '\n')[-1][0]
endfunction

function! s:ToggleOrientationVariable()
    let s:vtr_orientation = (s:vtr_orientation == "v" ? "h" : "v")
endfunction

function! s:BreakRunnerPaneToTempWindow()
    let targeted_cmd = s:TargetedTmuxCommand("break-pane", s:runner_pane)
    let full_command = join([targeted_cmd, "-d"])
    call s:SendTmuxCommand(full_command)
    let s:detached_window = s:LastWindowNumber()
    unlet s:runner_pane
endfunction

function! s:RunnerDimensionSpec()
    let dimensions = join(["-p", s:vtr_percentage, "-".s:vtr_orientation])
    return dimensions
endfunction

function! s:_ReattachPane()
    let join_cmd = join(["join-pane", "-s", ":".s:detached_window.".0",
        \ s:RunnerDimensionSpec()])
    call s:SendTmuxCommand(join_cmd)
    unlet s:detached_window
    let s:runner_pane = s:ActiveTmuxPaneNumber()
endfunction

function! s:ReattachPane()
    if !s:RequireDetachedPane()
        return
    endif
    call s:_ReattachPane()
    call s:FocusVimPane()
    if g:VtrClearOnReattach
        call s:SendClearSequence()
    endif
endfunction

function! s:ReorientRunner()
    if !s:RequireRunnerPane()
        return
    endif
    let temp_window = s:BreakRunnerPaneToTempWindow()
    call s:ToggleOrientationVariable()
    call s:_ReattachPane()
    call s:FocusVimPane()
    if g:VtrClearOnReorient
        call s:SendClearSequence()
    endif
endfunction

function! s:HighlightedPrompt(prompt)
    echohl String | let input = shellescape(input(a:prompt)) | echohl None
    return input
endfunction

function! s:FlushCommand()
    if exists("s:user_command")
        unlet s:user_command
    endif
endfunction

function! s:ResizeRunnerPane(...)
    if !s:RequireRunnerPane()
        return
    endif
    if exists("a:1") && a:1 != ""
        let new_percent = shellescape(a:1)
    else
        let new_percent = s:HighlightedPrompt("Runner screen percentage: ")
    endif
    let pane_dimensions =  s:RunnerPaneDimensions()
    let expand = (eval(join([new_percent, '>', s:vtr_percentage])))
    if s:vtr_orientation == "v"
        let relevant_dimension = pane_dimensions['height']
        let direction = expand ? '-U' : '-D'
    else
        let relevant_dimension = pane_dimensions['width']
        let direction = expand ? '-L' : '-R'
    endif
    let inputs = [relevant_dimension, '*', new_percent,
        \ '/',  s:vtr_percentage]
    let new_lines = eval(join(inputs)) " Not sure why I need to use eval...?
    let lines_delta = abs(relevant_dimension - new_lines)
    let targeted_cmd = s:TargetedTmuxCommand("resize-pane", s:runner_pane)
    let full_command = join([targeted_cmd, direction, lines_delta])
    call s:SendTmuxCommand(full_command)
    let s:vtr_percentage = new_percent
    if g:VtrClearOnResize
        call s:SendClearSequence()
    endif
endfunction

function! s:SendCommandToRunner(...)
    if exists("a:1") && a:1 != ""
        let s:user_command = shellescape(a:1)
    endif
    if !exists("s:user_command")
        let s:user_command = s:HighlightedPrompt(g:VtrPrompt)
    endif
    let escaped_empty_string = "''"
    if s:user_command == escaped_empty_string
        unlet s:user_command
        echohl ErrorMsg | echom "VTR: command string required" | echohl None
        return
    endif
    call s:EnsureRunnerPane()
    if g:VtrClearBeforeSend
        call s:SendClearSequence()
    endif
    call s:SendKeys(s:user_command)
endfunction

function! s:EnsureRunnerPane()
    if exists('s:detached_window')
        call s:ReattachPane()
    elseif exists('s:runner_pane')
        return
    else
        call s:OpenRunnerPane()
    endif
endfunction

function! VtrSendCommand(command)
    call s:EnsureRunnerPane()
    let escaped_command = shellescape(a:command)
    call s:SendKeys(escaped_command)
endfunction

function! s:DefineCommands()
    command! -nargs=? VtrSendCommandToRunner call s:SendCommandToRunner(<f-args>)
    command! -nargs=? VtrResizeRunner call s:ResizeRunnerPane(<args>)
    command! VtrOpenRunner :call s:EnsureRunnerPane()
    command! VtrKillRunner :call s:KillRunnerPane()
    command! VtrFocusRunner :call s:FocusRunnerPane()
    command! VtrReorientRunner :call s:ReorientRunner()
    command! VtrDetachRunner :call s:DetachRunnerPane()
    command! VtrReattachRunner :call s:ReattachPane()
    command! VtrClearRunner :call s:SendClearSequence()
    command! VtrFlushCommand :call s:FlushCommand()
endfunction

function! s:DefineKeymaps()
    if g:VtrUseVtrMaps
        nmap ,rr :VtrResizeRunner<cr>
        nmap ,ror :VtrReorientRunner<cr>
        nmap ,sc :VtrSendCommandToRunner<cr>
        nmap ,or :VtrOpenRunner<cr>
        nmap ,kr :VtrKillRunner<cr>
        nmap ,fr :VtrFocusRunner<cr>
        nmap ,dr :VtrDetachRunner<cr>
        nmap ,ar :VtrReattachRunner<cr>
        nmap ,cr :VtrClearRunner<cr>
        nmap ,fc :VtrFlushCommand<cr>
    endif
endfunction

function! s:InitializeVariables()
    call s:InitVariable("g:VtrPercentage", 20)
    call s:InitVariable("g:VtrOrientation", "v")
    call s:InitVariable("g:VtrInitialCommand", "")
    call s:InitVariable("g:VtrGitCdUpOnOpen", 0)
    call s:InitVariable("g:VtrClearBeforeSend", 1)
    call s:InitVariable("g:VtrPrompt", "Command to run: ")
    call s:InitVariable("g:VtrUseVtrMaps", 0)
    call s:InitVariable("g:VtrClearOnResize", 0)
    call s:InitVariable("g:VtrClearOnReorient", 1)
    call s:InitVariable("g:VtrClearOnReattach", 1)
    call s:InitVariable("g:VtrDetachedName", "VTR_Pane")
    call s:InitVariable("g:VtrInitTimeout", 450)
    call s:InitVariable("g:VtrClearSequence", "")
    let s:vtr_percentage = g:VtrPercentage
    let s:vtr_orientation = g:VtrOrientation
endfunction


call s:InitializeVariables()
call s:DefineCommands()
call s:DefineKeymaps()

" vim: set fdm=marker
