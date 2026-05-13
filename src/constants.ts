import { homedir } from 'node:os';
import { join } from 'node:path';

function getDefaultDataDir(): string {
  if (process.platform === 'win32') {
    return join(process.env.APPDATA || process.env.LOCALAPPDATA || homedir(), 'wechat-claude-code');
  }
  return join(homedir(), '.wechat-claude-code');
}

export const DATA_DIR = process.env.WCC_DATA_DIR || getDefaultDataDir();
