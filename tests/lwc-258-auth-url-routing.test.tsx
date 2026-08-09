import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, cleanup, render, waitFor } from '@testing-library/react';
import React from 'react';

if (!(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT) {
  (globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
}

const PRODUCT_API_URL = 'https://product.example.rayer.idv.tw';
const AUTH_URL = 'https://auth.example.rayer.idv.tw';

const AUTH_ENDPOINTS = {
  login: '/api/v1/auth/login',
  refresh: '/api/v1/auth/refresh',
  logout: '/api/v1/auth/logout',
  register: '/api/v1/auth/register',
};
const PRODUCT_ENDPOINT = '/api/v1/public/version';

type RequestRecord = { url: string; init?: RequestInit };

function createFetchStub(authUrl = AUTH_URL) {
  const requests: RequestRecord[] = [];
  const normalizedAuthUrl = authUrl.replace(/\/+$/, '');
  const normalizedProductUrl = PRODUCT_API_URL.replace(/\/+$/, '');

  const fetchStub: typeof globalThis.fetch = vi.fn(async (url, init) => {
    const target = String(url);
    const pathname = (() => {
      try {
        return new URL(target).pathname;
      } catch {
        return target.startsWith('/') ? target : `/${target}`;
      }
    })();
    requests.push({ url: target, init: init ?? {} });

    if (target === `${normalizedAuthUrl}${AUTH_ENDPOINTS.login}` || pathname === AUTH_ENDPOINTS.login) {
      return Response.json({ access_token: 'access', user: { id: 'user', email: 'user@example.com' } });
    }
    if (target === `${normalizedAuthUrl}${AUTH_ENDPOINTS.refresh}` || pathname === AUTH_ENDPOINTS.refresh) {
      return Response.json({ access_token: 'refreshed', user: { id: 'refreshed', email: 'user@example.com' } });
    }
    if (target === `${normalizedAuthUrl}${AUTH_ENDPOINTS.logout}` || pathname === AUTH_ENDPOINTS.logout) {
      return new Response(null, { status: 204 });
    }
    if (target === `${normalizedAuthUrl}${AUTH_ENDPOINTS.register}` || pathname === AUTH_ENDPOINTS.register) {
      return Response.json({
        token: 'registered',
        user_id: 'new-user',
        email: 'new@example.com',
      });
    }
    if (target === `${normalizedProductUrl}${PRODUCT_ENDPOINT}` || pathname === PRODUCT_ENDPOINT) {
      return Response.json({
        product_version: '1.2.3',
        commit: 'abc',
        branch: 'main',
        tag: '',
        image_tag: 'img',
        service: 'llm-wiki-bff',
        revision: 'rev',
      });
    }

    return new Response(null, { status: 404 });
  });

  return { fetchStub, requests };
}

function createStorage() {
  const data = new Map<string, string>();

  return {
    getItem: vi.fn((key: string) => data.get(key) ?? null),
    setItem: vi.fn((key: string, value: string) => {
      data.set(key, String(value));
    }),
    removeItem: vi.fn((key: string) => {
      data.delete(key);
    }),
  };
}

async function loadModules() {
  vi.resetModules();
  const auth = await import('../src/lib/auth.tsx');
  const api = await import('../src/lib/api.ts');
  return { auth, api };
}

describe('LWC-258 auth API base URL routing', () => {
  let storage: ReturnType<typeof createStorage>;
  let originalApiUrl: string | undefined;
  let originalAuthUrl: string | undefined;

  beforeEach(() => {
    storage = createStorage();
    originalApiUrl = process.env.NEXT_PUBLIC_API_URL;
    originalAuthUrl = process.env.NEXT_PUBLIC_AUTH_URL;
    process.env.NEXT_PUBLIC_API_URL = PRODUCT_API_URL;
    process.env.NEXT_PUBLIC_AUTH_URL = AUTH_URL;
    vi.stubGlobal('localStorage', storage);
  });

  afterEach(() => {
    if (originalApiUrl === undefined) {
      delete process.env.NEXT_PUBLIC_API_URL;
    } else {
      process.env.NEXT_PUBLIC_API_URL = originalApiUrl;
    }
    if (originalAuthUrl === undefined) {
      delete process.env.NEXT_PUBLIC_AUTH_URL;
    } else {
      process.env.NEXT_PUBLIC_AUTH_URL = originalAuthUrl;
    }

    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('routes auth requests to NEXT_PUBLIC_AUTH_URL while product calls stay on NEXT_PUBLIC_API_URL', async () => {
    const { fetchStub, requests } = createFetchStub(PRODUCT_API_URL);
    const originalFetch = globalThis.fetch;
    globalThis.fetch = fetchStub;
    const { auth, api } = await loadModules();

    try {
      let authContext: ReturnType<typeof auth.useAuth> | null = null;
      const Probe = () => {
        const context = auth.useAuth();
        React.useEffect(() => {
          authContext = context;
        }, [context]);

        return null;
      };

      render(
        <auth.AuthProvider>
          <Probe />
        </auth.AuthProvider>,
      );

      const resolvedAuthContext: ReturnType<typeof auth.useAuth> = await waitFor(() => {
        if (!authContext) {
          throw new Error('Auth context missing');
        }

        return authContext;
      });

      await act(async () => {
        await resolvedAuthContext.login('user@example.com', 'password123');
        await resolvedAuthContext.register('new@example.com', 'new-password123');
        await resolvedAuthContext.refreshAccessToken();
        await resolvedAuthContext.logout();
      });

      await api.getBuildInfo();

      const requestFor = (url: string) => requests.find((request) => request.url === url);
      const authCalls = requests.filter((request) => request.url.includes('/api/v1/auth/'));
      const apiCall = requestFor(`${PRODUCT_API_URL}${PRODUCT_ENDPOINT}`);
      const wrongAuthCall = requests.find((request) => request.url.startsWith(`${PRODUCT_API_URL}/api/v1/auth/`));

      expect(wrongAuthCall).toBeUndefined();
      expect(authCalls.length).toBeGreaterThanOrEqual(4);
      expect(requestFor(`${AUTH_URL}${AUTH_ENDPOINTS.login}`)?.init).toMatchObject({
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
      });
      expect(requestFor(`${AUTH_URL}${AUTH_ENDPOINTS.register}`)?.init).toMatchObject({
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
      });
      expect(requestFor(`${AUTH_URL}${AUTH_ENDPOINTS.refresh}`)?.init).toMatchObject({
        method: 'POST',
        credentials: 'include',
      });
      expect(requestFor(`${AUTH_URL}${AUTH_ENDPOINTS.logout}`)?.init).toMatchObject({
        method: 'POST',
        credentials: 'include',
      });
      expect(apiCall).toMatchObject({
        url: `${PRODUCT_API_URL}${PRODUCT_ENDPOINT}`,
        init: { method: 'GET', credentials: 'omit' },
      });
      expect(requestFor(`${AUTH_URL}${AUTH_ENDPOINTS.register}`)).toBeDefined();
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('falls back to NEXT_PUBLIC_API_URL when NEXT_PUBLIC_AUTH_URL is not set', async () => {
    const { fetchStub, requests } = createFetchStub(PRODUCT_API_URL);
    const originalFetch = globalThis.fetch;
    globalThis.fetch = fetchStub;
    const originalAuthUrl = process.env.NEXT_PUBLIC_AUTH_URL;

    delete process.env.NEXT_PUBLIC_AUTH_URL;
    const { auth } = await loadModules();

    try {
      let authContext: ReturnType<typeof auth.useAuth> | null = null;
      const Probe = () => {
        const context = auth.useAuth();
        React.useEffect(() => {
          authContext = context;
        }, [context]);

        return null;
      };

      render(
        <auth.AuthProvider>
          <Probe />
        </auth.AuthProvider>,
      );

      const resolvedAuthContext: ReturnType<typeof auth.useAuth> = await waitFor(() => {
        if (!authContext) {
          throw new Error('Auth context missing');
        }

        return authContext;
      });

      await act(async () => {
        await resolvedAuthContext.login('fallback@example.com', 'password123');
      });

      const requestFor = (url: string) => requests.find((request) => request.url === url);
      expect(requestFor(`${PRODUCT_API_URL}${AUTH_ENDPOINTS.login}`)).toBeDefined();
      expect(requestFor(`${AUTH_URL}${AUTH_ENDPOINTS.login}`)).toBeUndefined();
      expect(requestFor(`${PRODUCT_API_URL}${AUTH_ENDPOINTS.login}`)?.init).toMatchObject({
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
      });
    } finally {
      if (originalAuthUrl === undefined) {
        delete process.env.NEXT_PUBLIC_AUTH_URL;
      } else {
        process.env.NEXT_PUBLIC_AUTH_URL = originalAuthUrl;
      }
      globalThis.fetch = originalFetch;
      vi.resetModules();
    }
  });
});
