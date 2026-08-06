import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';

if (!(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT) {
  (globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
}

const mocks = vi.hoisted(() => ({
  currentProject: { id: 'project-a', name: 'Project A' },
  getConcept: vi.fn(),
  getConcepts: vi.fn(),
  getStatus: vi.fn(),
  searchWiki: vi.fn(),
}));

vi.mock('@/lib/api', async () => {
  const actual = await vi.importActual<typeof import('@/lib/api')>('@/lib/api');
  return { ...actual, getConcept: mocks.getConcept, getConcepts: mocks.getConcepts, getStatus: mocks.getStatus, searchWiki: mocks.searchWiki };
});

vi.mock('@/lib/i18n', () => ({ useT: () => ({ t: (key: string) => key }) }));
vi.mock('@/components/WorkspaceProvider', () => ({ useWorkspace: () => ({ currentProject: mocks.currentProject }) }));
vi.mock('@/components/NavigationBlocker', async () => {
  const actual = await vi.importActual<typeof import('@/components/NavigationBlocker')>('@/components/NavigationBlocker');
  return {
    ...actual,
    NavigationLink: ({ href, children, onClick, ...props }: { href: string; children: React.ReactNode; onClick?: React.MouseEventHandler }) => (
      <a href={href} onClick={onClick} {...props}>{children}</a>
    ),
    useNavigationBlocker: () => ({ confirmNavigation: () => true, consumeCapturedConfirmation: () => false, setBlocked: () => undefined }),
  };
});

import { HomeClient } from '@/components/HomeClient';

beforeEach(() => {
  mocks.getStatus.mockResolvedValue({ sourcesCount: 0, conceptsCount: 1, rawCount: 0, suggestedQueries: [], raw: {} });
  mocks.getConcepts.mockResolvedValue([]);
  mocks.searchWiki.mockResolvedValue({
    results: [],
    aiAnswer: '## Key points\n\n- **Bold** item with `code`\n- second item\n\n1. First\n2. Second\n\nSee [Concept].\n\n<script>alert(1)</script>',
    citations: [{ text: 'Concept', slug: 'concept', id: 'concept-id', type: 'concept' }],
  });
  mocks.getConcept.mockResolvedValue({ slug: 'concept', id: 'concept-id', title: 'Concept', content: 'Concept content.', raw: '' });
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('LWC-15 AI-answer Markdown rendering', () => {
  it('renders block Markdown semantically while preserving inline formatting and citation buttons', async () => {
    render(<HomeClient />);
    const input = await screen.findByRole('textbox');
    fireEvent.change(input, { target: { value: 'topic' } });
    fireEvent.click(screen.getByRole('button', { name: 'Demo.search' }));

    expect(await screen.findByRole('heading', { name: 'Key points', level: 2 })).toBeTruthy();
    expect(screen.getAllByRole('list')).toHaveLength(2);
    expect(screen.getAllByRole('listitem')).toHaveLength(4);
    expect(screen.getByText('Bold').tagName).toBe('STRONG');
    expect(screen.getByText('code').tagName).toBe('CODE');
    expect(screen.queryByRole('script')).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Concept' }));
    await waitFor(() => expect(screen.getByRole('dialog')).toBeTruthy());
    expect(screen.getByText('Concept content.')).toBeTruthy();
  });
});
