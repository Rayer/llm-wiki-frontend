'use client';

import { type ReactNode, useCallback, useEffect, useState } from 'react';
import { RefreshCw, ShieldAlert } from 'lucide-react';
import {
  getAdminProjects,
  getAdminUsers,
  type AdminProject,
  type AdminUser,
} from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { Badge } from './ui/Badge';
import { Surface } from './ui/Surface';

type Tab = 'projects' | 'users';

export function AdminClient() {
  const { hydrated, user } = useAuth();
  const [tab, setTab] = useState<Tab>('projects');
  const [projects, setProjects] = useState<AdminProject[]>([]);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [projectsLoading, setProjectsLoading] = useState(false);
  const [usersLoading, setUsersLoading] = useState(false);
  const [projectsError, setProjectsError] = useState('');
  const [usersError, setUsersError] = useState('');
  const isAdmin = user?.role === 'admin';
  const accessDenied = user?.role !== 'admin';

  const loadProjects = useCallback(async () => {
    setProjectsLoading(true);
    setProjectsError('');
    try {
      setProjects(await getAdminProjects());
    } catch (error) {
      setProjectsError(error instanceof Error ? error.message : 'Unable to load projects.');
    } finally {
      setProjectsLoading(false);
    }
  }, []);

  const loadUsers = useCallback(async () => {
    setUsersLoading(true);
    setUsersError('');
    try {
      setUsers(await getAdminUsers());
    } catch (error) {
      setUsersError(error instanceof Error ? error.message : 'Unable to load users.');
    } finally {
      setUsersLoading(false);
    }
  }, []);

  const refreshActive = useCallback(() => {
    return tab === 'projects' ? loadProjects() : loadUsers();
  }, [loadProjects, loadUsers, tab]);

  useEffect(() => {
    if (!hydrated || !isAdmin) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- kick off initial admin reads after auth hydration
    void loadProjects();
    void loadUsers();
  }, [hydrated, isAdmin, loadProjects, loadUsers]);

  if (!hydrated) {
    return <div className="py-20 text-center text-sm text-zinc-500">Loading...</div>;
  }

  if (accessDenied) {
    return (
      <Surface variant="glass" className="mx-auto max-w-lg p-6 text-center">
        <ShieldAlert className="mx-auto size-8 text-amber-300" aria-hidden="true" />
        <h1 className="mt-4 text-xl font-semibold text-white">Admin access required</h1>
        <p className="mt-2 text-sm text-zinc-400">
          Your account does not have permission to use this console.
        </p>
      </Surface>
    );
  }

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl font-semibold tracking-tight text-white sm:text-4xl">Admin</h1>
          <p className="mt-2 max-w-2xl text-zinc-400">
            Manage projects, users, and pipeline operations.
          </p>
        </div>
        <button
          type="button"
          onClick={() => void refreshActive()}
          className="inline-flex min-h-11 items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-3 text-sm font-medium text-zinc-200 transition hover:bg-white/10"
        >
          <RefreshCw className="size-4" aria-hidden="true" />
          Refresh
        </button>
      </header>

      <Surface variant="glass" className="p-2">
        <div className="flex gap-1">
          <TabButton active={tab === 'projects'} onClick={() => setTab('projects')}>
            Projects
          </TabButton>
          <TabButton active={tab === 'users'} onClick={() => setTab('users')}>
            Users
          </TabButton>
        </div>
      </Surface>

      {tab === 'projects' ? (
        <ProjectsTable
          projects={projects}
          loading={projectsLoading}
          error={projectsError}
          onRetry={loadProjects}
        />
      ) : (
        <UsersTable users={users} loading={usersLoading} error={usersError} onRetry={loadUsers} />
      )}
    </div>
  );
}

function TabButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`min-h-10 rounded-md px-4 text-sm font-medium transition ${
        active ? 'bg-white/10 text-white' : 'text-zinc-400 hover:bg-white/5 hover:text-zinc-200'
      }`}
    >
      {children}
    </button>
  );
}

function ProjectsTable({
  projects,
  loading,
  error,
  onRetry,
}: {
  projects: AdminProject[];
  loading: boolean;
  error: string;
  onRetry: () => void;
}) {
  return (
    <Surface variant="glass" className="overflow-hidden">
      <TableStatus
        loading={loading}
        error={error}
        empty={!loading && projects.length === 0}
        emptyLabel="No projects found."
        onRetry={onRetry}
      />
      <div className="overflow-x-auto">
        <table className="w-full min-w-[760px] text-left text-sm">
          <thead className="border-b border-white/10 text-xs uppercase text-zinc-500">
            <tr>
              <th className="px-4 py-3 font-medium">Project name</th>
              <th className="px-4 py-3 font-medium">User ID</th>
              <th className="px-4 py-3 font-medium">Concept count</th>
              <th className="px-4 py-3 font-medium">Source count</th>
              <th className="px-4 py-3 text-right font-medium">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/8">
            {projects.map((project) => (
              <tr key={project.id}>
                <td className="px-4 py-3 font-medium text-white">{project.name}</td>
                <td className="px-4 py-3 font-mono text-xs text-zinc-500">
                  {project.userId || '—'}
                </td>
                <td className="px-4 py-3 tabular-nums text-zinc-300">{project.conceptCount}</td>
                <td className="px-4 py-3 tabular-nums text-zinc-300">{project.sourceCount}</td>
                <td className="px-4 py-3 text-right text-zinc-500">Actions</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Surface>
  );
}

function UsersTable({
  users,
  loading,
  error,
  onRetry,
}: {
  users: AdminUser[];
  loading: boolean;
  error: string;
  onRetry: () => void;
}) {
  return (
    <Surface variant="glass" className="overflow-hidden">
      <TableStatus
        loading={loading}
        error={error}
        empty={!loading && users.length === 0}
        emptyLabel="No users found."
        onRetry={onRetry}
      />
      <div className="overflow-x-auto">
        <table className="w-full min-w-[760px] text-left text-sm">
          <thead className="border-b border-white/10 text-xs uppercase text-zinc-500">
            <tr>
              <th className="px-4 py-3 font-medium">Email</th>
              <th className="px-4 py-3 font-medium">Role</th>
              <th className="px-4 py-3 font-medium">Project count</th>
              <th className="px-4 py-3 text-right font-medium">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/8">
            {users.map((user) => (
              <tr key={user.id}>
                <td className="px-4 py-3 font-medium text-white">{user.email}</td>
                <td className="px-4 py-3">
                  <Badge variant={user.role === 'admin' ? 'accent' : 'muted'}>{user.role}</Badge>
                </td>
                <td className="px-4 py-3 tabular-nums text-zinc-300">{user.projectCount}</td>
                <td className="px-4 py-3 text-right text-zinc-500">Actions</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Surface>
  );
}

function TableStatus({
  loading,
  error,
  empty,
  emptyLabel,
  onRetry,
}: {
  loading: boolean;
  error: string;
  empty: boolean;
  emptyLabel: string;
  onRetry: () => void;
}) {
  if (loading) {
    return <p className="border-b border-white/10 px-4 py-3 text-sm text-zinc-500">Loading...</p>;
  }

  if (error) {
    return (
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-white/10 px-4 py-3">
        <p className="text-sm text-amber-300">{error}</p>
        <button
          type="button"
          onClick={onRetry}
          className="text-sm font-medium text-zinc-300 transition hover:text-white"
        >
          Retry
        </button>
      </div>
    );
  }

  if (empty) {
    return <p className="border-b border-white/10 px-4 py-3 text-sm text-zinc-500">{emptyLabel}</p>;
  }

  return null;
}
