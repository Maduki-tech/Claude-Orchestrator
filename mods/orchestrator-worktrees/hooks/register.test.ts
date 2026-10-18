import { expect, test } from 'claude-code/testing'

import { parse, stateOf } from './register'

const OUT = `feature/blog-empty
  worktree: /r-wt
  agent:    blog-empty
  goal:     Feature: show empty state
  changed:  a.txt b.txt
  last:     2026-10-11T08:36:11+02:00 Question: keep the old route?
fix/login
  worktree: /r-wt2
  agent:    none running
  goal:     (no brief)
  changed:  nothing yet
  last:     no report yet
`

const BAND = { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 80, scroll: { offset: 0, bodyRows: 3 }, view: {} }

test('parse reads every task block', () => {
  const tasks = parse(OUT)
  expect(tasks.map(t => t.branch)).toEqual(['feature/blog-empty', 'fix/login'])
  expect(tasks[0]).toMatchObject({ agent: 'blog-empty', changed: 'a.txt b.txt', goal: 'Feature: show empty state' })
  expect(parse('list-tasks: no task worktrees\n')).toEqual([])
})

test('stateOf maps the last report to a state', () => {
  const [question, none] = parse(OUT)
  expect(stateOf(question!).label).toBe('question')
  expect(stateOf(none!).label).toBe('working')
  const at = (message: string) => stateOf({ ...none!, last: `2026-10-11T08:36:11+02:00 ${message}` }).label
  expect(at('Ready for review: 2 files')).toBe('review')
  expect(at('Done: merged https://github.com/o/r/pull/7')).toBe('merged')
  expect(at('Done: https://github.com/o/r/pull/7')).toBe('merged')
  expect(at('Done: unmerged feature/x')).toBe('to merge')
  expect(at('Done: CI failed on lint, stopped')).toBe('stopped')
  expect(at('Working on the review of done items')).toBe('working')
})

test('/worktrees opens the pane', async ($, on) => {
  const opened: string[] = []
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  const { text } = await $.command.run({ command: 'worktrees', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } })
  expect(text).toBe('Worktrees pane opened.')
  expect(opened).toEqual(['worktrees'])
})

test('band summarizes the tasks and its button opens the pane', async ($, on) => {
  on('process.run', () => ({ value: { exitCode: 0, stdout: OUT, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  const opened: string[] = []
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('session.start', (_$, e) => e)
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('clock.every', () => ({ value: undefined }))
  await $.session.start({ cwd: '/r', surface: 'terminal', isInteractive: true })
  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ plugin: 'orchestrator-worktrees', surface, component: 'AbovePrompt', props: BAND })
    expect(await band.find({ text: /2 worktrees/ })).toBeDefined()
    expect(await band.find({ text: /1 question/ })).toBeDefined()
    await band.press({ key: 'open' })
  }
  expect(opened).toEqual(['worktrees', 'worktrees'])
})

test('Jump focuses a running agent, else opens and focuses the worktree workspace', async ($, on) => {
  const ran: string[] = []
  const ok = (stdout: string) => ({ value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
  on('process.run', (_$, e) => {
    const argv = e.argv.join(' ')
    if (argv.includes('list-tasks.sh')) return ok(OUT)
    ran.push(argv)
    if (argv.startsWith('git ')) return ok('/repo/.git\n')
    if (argv.startsWith('herdr worktree open')) return ok('{"result":{"workspace":{"workspace_id":"w7"}}}')
    return ok('')
  })
  on('session.start', (_$, e) => e)
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('clock.every', () => ({ value: undefined }))
  await $.session.start({ cwd: '/r', surface: 'terminal', isInteractive: true })

  const pane = await $.ui.mount({ plugin: 'orchestrator-worktrees', surface: 'terminal', component: 'Pane', requestId: 'worktrees', props: {} as never })
  await pane.press({ key: 'jump-feature/blog-empty' })
  await pane.press({ key: 'jump-fix/login' })
  expect(ran).toEqual([
    'herdr agent focus blog-empty',
    'git -C /r-wt2 rev-parse --path-format=absolute --git-common-dir',
    'herdr worktree open --cwd /repo --path /r-wt2',
    'herdr workspace focus w7',
  ])
})
