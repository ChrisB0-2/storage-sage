import React from 'react'
import CIcon from '@coreui/icons-react'
import {
  cilSpeedometer,
  cilSettings,
  cilHistory,
  cilMedicalCross,
  cilStorage,
} from '@coreui/icons'
import { CNavItem, CNavTitle } from '@coreui/react'

const _nav = [
  {
    component: CNavTitle,
    name: 'StorageSage',
  },
  {
    component: CNavItem,
    name: 'Overview',
    to: '/storagesage/overview',
    icon: <CIcon icon={cilSpeedometer} customClassName="nav-icon" />,
    badge: {
      color: 'info',
      text: 'MAIN',
    },
  },
  {
    component: CNavItem,
    name: 'Cleanup Rules',
    to: '/storagesage/cleanup-rules',
    icon: <CIcon icon={cilSettings} customClassName="nav-icon" />,
  },
  {
    component: CNavItem,
    name: 'Deletion History',
    to: '/storagesage/deletions',
    icon: <CIcon icon={cilHistory} customClassName="nav-icon" />,
  },
  {
    component: CNavItem,
    name: 'System Health',
    to: '/storagesage/system-health',
    icon: <CIcon icon={cilMedicalCross} customClassName="nav-icon" />,
  },
]

export default _nav
