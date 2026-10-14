export type Task = {
  branch: string
  worktree: string
  agent: string
  goal: string
  changed: string
  last: string
}

declare module 'claude-code' {
  interface PluginState {
    'orchestrator-worktrees': { tasks: Task[] }
  }
}
