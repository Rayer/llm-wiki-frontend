import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { act } from 'react';

if (!(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT) {
  (globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
}

const mocks = vi.hoisted(() => ({
  currentProject: { id: 'project-a', name: 'Project A' },
  getConcepts: vi.fn(),
  getStatus: vi.fn(),
  searchWiki: vi.fn(),
}));

vi.mock('@/lib/api', async () => {
  const actual = await vi.importActual<typeof import('@/lib/api')>('@/lib/api');
  return {
    ...actual,
    getConcepts: mocks.getConcepts,
    getStatus: mocks.getStatus,
    searchWiki: mocks.searchWiki,
  };
});

vi.mock('@/lib/i18n', () => ({
  useT: () => ({ t: (key: string) => key }),
}));

vi.mock('@/components/WorkspaceProvider', () => ({
  useWorkspace: () => ({ currentProject: mocks.currentProject }),
}));

vi.mock('@/components/NavigationBlocker', async () => {
  const actual = await vi.importActual<typeof import('@/components/NavigationBlocker')>('@/components/NavigationBlocker');
  return {
    ...actual,
    NavigationLink: ({ href, children, onClick, ...props }: {
      href: string;
      children: React.ReactNode;
      onClick?: React.MouseEventHandler;
    }) => (
      <a href={href} onClick={onClick} {...props}>
        {children}
      </a>
    ),
    useNavigationBlocker: () => ({
      confirmNavigation: () => true,
      consumeCapturedConfirmation: () => false,
      setBlocked: () => undefined,
    }),
  };
});

import { HomeClient } from '@/components/HomeClient';
import type { ApiStatus } from '@/lib/api';

const SEARCH_RESPONSE = {
  results: [],
  aiAnswer: '',
  citations: [],
};

function status(overrides: Partial<ApiStatus> = {}) {
  return {
    sourcesCount: 2,
    conceptsCount: 3,
    rawCount: 1,
    suggestedQueries: ['primary'],
    raw: {},
    ...overrides,
  } as ApiStatus;
}

function setMatchMedia(prefersReducedMotion: boolean) {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    configurable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: query === '(prefers-reduced-motion: reduce)' ? prefersReducedMotion : false,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  });
}

let replaceStateSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  setMatchMedia(false);
  mocks.getStatus.mockResolvedValue(status());
  mocks.getConcepts.mockResolvedValue([]);
  mocks.searchWiki.mockResolvedValue(SEARCH_RESPONSE);
  replaceStateSpy = vi.spyOn(window.history, 'replaceState').mockImplementation(() => undefined);
});

afterEach(() => {
  replaceStateSpy.mockRestore();
  cleanup();
  vi.clearAllMocks();
});

async function getSuggestedChip(label: string) {
  return screen.findByRole('button', { name: label });
}

async function getSearchButton() {
  return screen.findByRole('button', { name: 'Demo.search' });
}

async function waitForInitialSearchState() {
  await waitFor(() => {
    expect(mocks.getStatus).toHaveBeenCalledTimes(1);
    expect(mocks.getConcepts).toHaveBeenCalledTimes(1);
  });
}

async function getFormFromSearchButton() {
  const searchButton = await getSearchButton();
  const form = searchButton.closest('form');
  expect(form).not.toBeNull();
  return { form: form as HTMLFormElement, searchButton };
}

describe('LWC-248 home search submission contract', () => {
  it('does not submit when changing modes with a non-empty query', async () => {
    render(<HomeClient />);
    await waitForInitialSearchState();
    const queryInput = screen.getByRole('textbox');
    const fullMode = screen.getByRole('button', { name: 'Demo.full' });

    await act(async () => {
      fireEvent.change(queryInput, { target: { value: 'topic alpha' } });
      fireEvent.click(fullMode);
    });

    expect(mocks.searchWiki).toHaveBeenCalledTimes(0);
    expect(replaceStateSpy).toHaveBeenCalledTimes(0);
  });

  it('fills query from a suggested chip without searching or syncing URL', async () => {
    mocks.getStatus.mockResolvedValue(status({
      suggestedQueries: ['suggestion', 'chip suggestion'],
    }));

    render(<HomeClient />);
    await waitForInitialSearchState();
    const chip = await getSuggestedChip('chip suggestion');
    const queryInput = screen.getByRole('textbox');

    queryInput.focus();
    await act(async () => {
      fireEvent.click(chip);
    });

    expect((queryInput as HTMLInputElement).value).toBe('chip suggestion');
    expect(mocks.searchWiki).toHaveBeenCalledTimes(0);
    expect(replaceStateSpy).toHaveBeenCalledTimes(0);
    expect(window.location.search).toBe('');
    expect(document.activeElement).toBe(queryInput);
  });

  it('searches exactly once from Search button with current mode and syncs URL once', async () => {
    render(<HomeClient />);
    await waitForInitialSearchState();
    const queryInput = screen.getByRole('textbox');
    const fullMode = screen.getByRole('button', { name: 'Demo.full' });
    const searchButton = await getSearchButton();

    await act(async () => {
      fireEvent.change(queryInput, { target: { value: 'topic beta' } });
      fireEvent.click(fullMode);
    });
    expect(fullMode.className).toContain('bg-emerald-400/20');
    await act(async () => {
      fireEvent.click(searchButton);
    });

    expect(mocks.searchWiki).toHaveBeenCalledTimes(1);
    expect(mocks.searchWiki).toHaveBeenCalledWith('topic beta', 'full');
    expect(replaceStateSpy).toHaveBeenCalledTimes(1);
    expect(replaceStateSpy).toHaveBeenCalledWith(null, '', '/?q=topic+beta&mode=full');
  });

  it('submits the form (Enter-equivalent) exactly once with one URL sync', async () => {
    render(<HomeClient />);
    await waitForInitialSearchState();
    const queryInput = screen.getByRole('textbox');
    const { form } = await getFormFromSearchButton();

    await act(async () => {
      fireEvent.change(queryInput, { target: { value: 'topic gamma' } });
      fireEvent.submit(form);
    });

    expect(mocks.searchWiki).toHaveBeenCalledTimes(1);
    expect(mocks.searchWiki).toHaveBeenCalledWith('topic gamma', 'wiki');
    expect(replaceStateSpy).toHaveBeenCalledTimes(1);
    expect(replaceStateSpy).toHaveBeenCalledWith(null, '', '/?q=topic+gamma');
  });

  it('restarts the Search-button cue animation with distinct animation names on repeated chip clicks', async () => {
    mocks.getStatus.mockResolvedValue(status({
      suggestedQueries: ['suggestion', 'chip suggestion'],
    }));

    render(<HomeClient />);
    await waitForInitialSearchState();
    const chip = await getSuggestedChip('chip suggestion');
    const searchButton = await getSearchButton();

    await act(async () => {
      fireEvent.click(chip);
    });
    const firstCue = searchButton.getAttribute('data-search-cue');
    const firstCueAnimation = searchButton.getAttribute('data-search-cue-animation');

    await act(async () => {
      fireEvent.click(chip);
    });
    const secondCue = searchButton.getAttribute('data-search-cue');
    const secondCueAnimation = searchButton.getAttribute('data-search-cue-animation');

    expect(firstCue).toBe('1');
    expect(secondCue).toBe('2');
    expect(firstCue).not.toBe(secondCue);
    expect(firstCueAnimation).toBe('home-search-button-cue-gentle');
    expect(secondCueAnimation).toBe('home-search-button-cue-gentle-alt');
  });

  it('clears the Search-button cue after explicit form submission', async () => {
    mocks.getStatus.mockResolvedValue(status({
      suggestedQueries: ['suggestion', 'chip'],
    }));

    render(<HomeClient />);
    await waitForInitialSearchState();
    const queryInput = screen.getByRole('textbox');
    const searchButton = await getSearchButton();
    const { form } = await getFormFromSearchButton();
    const chip = await getSuggestedChip('chip');

    await act(async () => {
      fireEvent.change(queryInput, { target: { value: 'topic delta' } });
      fireEvent.click(chip);
      fireEvent.submit(form);
    });

    expect(searchButton.getAttribute('data-search-cue')).toBeNull();
  });

  it('keeps reduced-motion users motion-free while preserving the cue', async () => {
    setMatchMedia(true);
    mocks.getStatus.mockResolvedValue(status({
      suggestedQueries: ['suggestion', 'chip suggestion'],
    }));

    render(<HomeClient />);
    await waitForInitialSearchState();
    const chip = await getSuggestedChip('chip suggestion');
    const searchButton = await getSearchButton();

    await act(async () => {
      fireEvent.click(chip);
    });

    expect(searchButton.getAttribute('data-search-reduced-motion')).toBe('1');
    expect(searchButton.getAttribute('data-search-cue')).toBe('1');
  });
});
