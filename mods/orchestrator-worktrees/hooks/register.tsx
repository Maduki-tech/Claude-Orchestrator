import { atom, read, update } from 'claude-code'
import type { Color, EngineInterface, Register } from 'claude-code'

import type { Task } from '../types'

const LIST = ['sh', '-c', '"$HOME/.agents/skills/orchestrator/scripts/list-tasks.sh"']
const PANE = 'worktrees'
const tasks = atom({ plugin: 'orchestrator-worktrees', key: 'tasks' } as const, [])

// list-tasks.sh prints a branch line, then indented "key: value" lines.
export const parse = (out: string): Task[] =>
  out.trim().split(/\n(?=\S)/).flatMap(block => {
    const [branch, ...rest] = block.split('\n')
    if (!branch || !rest.length) return []
    const field = (key: string) =>
      rest.find(line => line.trimStart().startsWith(`${key}:`))?.replace(/^\s*\w+:\s*/, '') ?? ''

    return [{
      branch,
      worktree: field('worktree'),
      agent: field('agent'),
      goal: field('goal'),
      changed: field('changed'),
      last: field('last'),
    }]
  })

const STATES: [RegExp, string, Color][] = [
  [/plan ready/i, 'plan ready', 'warning'],
  [/ready for review/i, 'review', 'warning'],
  [/blocked|decision/i, 'blocked', 'error'],
  [/merged/i, 'merged', 'merged'],
  [/committed/i, 'committed', 'success'],
  [/done/i, 'done', 'success'],
]

export const stateOf = (task: Task): { label: string; color: Color } => {
  const message = task.last.replace(/^\S+\s/, '')
  const hit = task.last !== 'no report yet' && STATES.find(([re]) => re.test(message))

  return hit ? { label: hit[1], color: hit[2] } : { label: 'working', color: 'subtle' }
}

// A running worker: focus its agent pane. Otherwise open (or reuse) the
// worktree's Herdr workspace, which Herdr opens from the main checkout.
const jump = async ($: EngineInterface, task: Task) => {
  const run = async (argv: string[]) => {
    const { exitCode, stdout, stderr } = await $.process.run(argv)
    if (exitCode !== 0) throw new Error(stderr.trim() || stdout.trim() || `${argv[1]} exited ${exitCode}`)
    return stdout
  }
  try {
    if (task.agent !== 'none running') {
      await run(['herdr', 'agent', 'focus', task.agent])
      return
    }
    const common = await run(['git', '-C', task.worktree, 'rev-parse', '--path-format=absolute', '--git-common-dir'])
    const root = common.trim().replace(/\/\.git$/, '')
    const opened = JSON.parse(await run(['herdr', 'worktree', 'open', '--cwd', root, '--path', task.worktree]))
    await run(['herdr', 'workspace', 'focus', opened.result.workspace.workspace_id])
  } catch (error) {
    $.ui.toast(`Jump to ${task.branch} failed: ${(error as Error).message}`)
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'worktrees',
      description: 'Open the orchestrator worktrees pane',
    })
    const refresh = async () => {
      const { exitCode, stdout } = await $.process.run(LIST)
      await update($, tasks, () => (exitCode === 0 ? parse(stdout) : []))
    }
    void refresh()
    // ponytail: polls every 10s; watch the inbox file if that ever feels laggy
    $.clock.every(10_000, () => void refresh())

    return next(e)
  })

  on('command.run', { command: 'worktrees' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Worktrees' })

    return { text: 'Worktrees pane opened.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const list = await read($, tasks)
    if (e.props.hasSurvey || list.length === 0) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const counts = new Map<string, { n: number; color: Color }>()
    for (const task of list) {
      const { label, color } = stateOf(task)
      counts.set(label, { n: (counts.get(label)?.n ?? 0) + 1, color })
    }

    return (
      <Box>
        <Text>⎇ {list.length} worktree{list.length === 1 ? '' : 's'}</Text>
        {[...counts].map(([label, { n, color }]) => (
          <Text color={color}> · {n} {label}</Text>
        ))}
        <Text> </Text>
        <Button key="open" label="Open" onPress={() => $.ui.open({ id: PANE, title: 'Worktrees' })} />
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const list = await read($, tasks)

    return (
      <Box flexDirection="column">
        {list.length === 0 && <Text dimColor>No task worktrees.</Text>}
        {list.map(task => {
          const { label, color } = stateOf(task)
          const files = task.changed === 'nothing yet' ? 0 : task.changed.split(' ').length

          return (
            <Box flexDirection="column" marginBottom={1}>
              <Text>
                <Text color={color}>● </Text>
                <Text bold>{task.branch}</Text>
                <Text color={color}>  {label.toUpperCase()}</Text>
              </Text>
              <Box>
                <Text>  </Text>
                <Button key={`jump-${task.branch}`} label="Jump" onPress={() => jump($, task)} />
              </Box>
              <Text wrap="truncate-end">  {task.goal}</Text>
              <Text dimColor wrap="truncate-end">
                {'  '}{files} file{files === 1 ? '' : 's'} · agent: {task.agent}
              </Text>
              <Text dimColor wrap="truncate-end">  {task.last}</Text>
            </Box>
          )
        })}
      </Box>
    )
  })
}
