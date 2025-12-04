import React from 'react'

// StorageSage pages
const Overview = React.lazy(() => import('./views/storagesage/Overview'))
const CleanupRules = React.lazy(() => import('./views/storagesage/CleanupRules'))
const Deletions = React.lazy(() => import('./views/storagesage/Deletions'))
const SystemHealth = React.lazy(() => import('./views/storagesage/SystemHealth'))

const routes = [
  { path: '/', exact: true, name: 'Home' },
  { path: '/storagesage', name: 'StorageSage', element: Overview, exact: true },
  { path: '/storagesage/overview', name: 'Overview', element: Overview },
  { path: '/storagesage/cleanup-rules', name: 'Cleanup Rules', element: CleanupRules },
  { path: '/storagesage/deletions', name: 'Deletion History', element: Deletions },
  { path: '/storagesage/system-health', name: 'System Health', element: SystemHealth },
]

export default routes
