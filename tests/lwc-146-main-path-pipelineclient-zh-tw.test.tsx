import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import {
  queryByText,
  getByRole,
  getByText,
  screen,
  waitFor,
} from '@testing-library/dom';

if (!(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT) {
  (globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
}

const mockedQuota = {
  enforced: true,
  allowed: true,
  runs_today: 2,
  daily_limit: 5,
  new_raw_files: 4,
  min_new_raw: 1,
  already_running: false,
};

const mocks = vi.hoisted(() => ({
  currentProject: { id: 'project-a', name: 'Project A' },
  getPipelineStatus: vi.fn(),
  refreshNavCounts: vi.fn(),
}));
const testStorage = new Map<string, string>();

function installTestStorage() {
  const storageLike = {
    getItem: (key: string): string | null => testStorage.get(key) ?? null,
    setItem: (key: string, value: string) => {
      testStorage.set(key, String(value));
    },
    removeItem: (key: string) => {
      testStorage.delete(key);
    },
  };

  if (typeof globalThis.localStorage !== 'object') {
    (globalThis as { localStorage?: typeof storageLike }).localStorage = storageLike;
  }
  if (typeof window !== 'undefined' && typeof (window as { localStorage?: typeof storageLike }).localStorage !== 'object') {
    (window as { localStorage?: typeof storageLike }).localStorage = storageLike;
  }
}

vi.mock('@/lib/api', async () => {
  const actual = await vi.importActual<typeof import('@/lib/api')>('@/lib/api');
  return {
    ...actual,
    getPipelineStatus: mocks.getPipelineStatus,
  };
});

vi.mock('@/components/WorkspaceProvider', () => ({
  useWorkspace: () => ({
    currentProject: mocks.currentProject,
    isDemoSession: false,
    refreshNavCounts: mocks.refreshNavCounts,
  }),
}));

import { PipelineClient } from '@/components/PipelineClient';

const expectedQuotaLine = '今日執行：2/5 · 冷卻：無 · 新檔案：4';
let previousLocale: string | null | undefined;
let mountRoot: Root | null = null;
let mountContainer: HTMLDivElement | null = null;

beforeEach(() => {
  installTestStorage();
  previousLocale = window.localStorage.getItem('locale');
  window.localStorage.setItem('locale', 'zh-TW');
  window.dispatchEvent(new Event('locale-change'));
  mocks.getPipelineStatus.mockResolvedValue({
    quota: mockedQuota,
  });

  mountContainer = document.createElement('div');
  document.body.appendChild(mountContainer);
  mountRoot = createRoot(mountContainer);
  mountRoot.render(<PipelineClient />);
});

afterEach(async () => {
  await mountRoot?.unmount();
  if (mountContainer?.isConnected) {
    mountContainer.remove();
  }
  mountRoot = null;
  mountContainer = null;

  vi.clearAllMocks();

  if (previousLocale === null || previousLocale === undefined) {
    window.localStorage.removeItem('locale');
  } else {
    window.localStorage.setItem('locale', previousLocale);
  }
  window.dispatchEvent(new Event('locale-change'));
  testStorage.clear();
  previousLocale = undefined;
});

describe('LWC-146: main-path zh-TW pipeline content', () => {
  it('renders localized Pipeline add-content and run text in zh-TW', async () => {
    await waitFor(() => {
      expect(document.body.textContent).toBeTruthy();
    });

    expect(getByRole(document.body, 'heading', { name: '新增內容' })).toBeDefined();
    expect(getByText(document.body, '上傳 markdown 檔案或擷取網址，以建立知識資料來源。')).toBeDefined();
    expect(
      getByText(document.body, '可同時上傳多個檔案到 raw/ 目錄（最多 3 檔同時上傳）。'),
    ).toBeDefined();
    expect(getByRole(document.body, 'heading', { name: '擷取 URL' })).toBeDefined();
    expect(getByText(document.body, '抓取網頁內容並存為原文資料。')).toBeDefined();
    expect(getByText(document.body, '選擇')).toBeDefined();
    expect(getByRole(document.body, 'button', { name: '執行 Pipeline' })).toBeDefined();
    expect(
      getByText(document.body, 'ingest（分析原始筆記）→ compile（綜合 wiki 條目）→ lint（品質檢查）→ publish（自動核准）。'),
    ).toBeDefined();
    expect(getByText(document.body, '啟動 OLW pipeline 以整理、編譯並上架知識條目。')).toBeDefined();

    await waitFor(() => {
      expect(screen.getByTestId('pipeline-quota-line').textContent).toBe(expectedQuotaLine);
    });

    expect(queryByText(document.body, 'Add Content')).toBeNull();
    expect(queryByText(document.body, 'Upload Files')).toBeNull();
    expect(queryByText(document.body, 'Scrape URL')).toBeNull();
    expect(queryByText(document.body, 'Run Pipeline')).toBeNull();
    expect(queryByText(document.body, 'Select')).toBeNull();
  });
});
