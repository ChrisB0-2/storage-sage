import React, { useState, useEffect } from 'react'
import {
  CCard,
  CCardBody,
  CCardHeader,
  CCol,
  CRow,
  CSpinner,
  CAlert,
  CButton,
  CBadge,
  CListGroup,
  CListGroupItem,
} from '@coreui/react'
import CIcon from '@coreui/icons-react'
import { cilReload, cilCheckCircle, cilXCircle, cilWarning } from '@coreui/icons'
import { getHealth, getMetrics } from '../../api/storageSageClient'

const SystemHealth = () => {
  const [health, setHealth] = useState(null)
  const [metrics, setMetrics] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [lastUpdate, setLastUpdate] = useState(null)

  const fetchHealth = async () => {
    try {
      setLoading(true)
      setError(null)

      // Fetch both health and metrics in parallel
      const [healthData, metricsData] = await Promise.all([
        getHealth().catch(err => ({ status: 'error', error: err.message })),
        getMetrics().catch(err => null)
      ])

      setHealth(healthData)
      setMetrics(metricsData)
      setLastUpdate(new Date())
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchHealth()
    // Auto-refresh every 30 seconds
    const interval = setInterval(fetchHealth, 30000)
    return () => clearInterval(interval)
  }, [])

  const getStatusBadge = (status) => {
    const badges = {
      healthy: { color: 'success', icon: cilCheckCircle, text: 'Healthy' },
      warning: { color: 'warning', icon: cilWarning, text: 'Warning' },
      critical: { color: 'danger', icon: cilXCircle, text: 'Critical' },
      error: { color: 'danger', icon: cilXCircle, text: 'Error' },
      unknown: { color: 'secondary', icon: cilWarning, text: 'Unknown' },
    }
    return badges[status] || badges.unknown
  }

  const formatUptime = (seconds) => {
    if (!seconds) return 'N/A'
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)

    const parts = []
    if (days > 0) parts.push(`${days}d`)
    if (hours > 0) parts.push(`${hours}h`)
    if (minutes > 0) parts.push(`${minutes}m`)

    return parts.join(' ') || '< 1m'
  }

  const getOverallStatus = () => {
    if (!health) return 'unknown'
    if (health.status === 'error') return 'error'

    // Check disk usage from metrics
    if (metrics?.disk) {
      const usagePercent = (metrics.disk.used / metrics.disk.total) * 100
      if (usagePercent >= 90) return 'critical'
      if (usagePercent >= 75) return 'warning'
    }

    return health.status || 'healthy'
  }

  if (loading && !health) {
    return (
      <div className="text-center">
        <CSpinner color="primary" />
        <p className="mt-2">Loading system health...</p>
      </div>
    )
  }

  const overallStatus = getOverallStatus()
  const statusBadge = getStatusBadge(overallStatus)

  return (
    <>
      <CRow>
        <CCol xs={12}>
          <CCard className="mb-4">
            <CCardHeader className="d-flex justify-content-between align-items-center">
              <strong>System Health Status</strong>
              <CButton color="primary" size="sm" onClick={fetchHealth} disabled={loading}>
                <CIcon icon={cilReload} className="me-1" />
                Refresh
              </CButton>
            </CCardHeader>
            <CCardBody>
              {error && (
                <CAlert color="danger" dismissible onClose={() => setError(null)}>
                  {error}
                </CAlert>
              )}
              {lastUpdate && (
                <small className="text-muted">
                  Last updated: {lastUpdate.toLocaleTimeString()}
                </small>
              )}
            </CCardBody>
          </CCard>
        </CCol>
      </CRow>

      {/* Overall Status */}
      <CRow>
        <CCol xs={12}>
          <CCard className="mb-4 text-center">
            <CCardBody className="py-5">
              <CIcon icon={statusBadge.icon} size="4xl" className={`text-${statusBadge.color}`} />
              <h2 className="mt-3 mb-2">System Status</h2>
              <CBadge color={statusBadge.color} className="fs-5 px-4 py-2">
                {statusBadge.text}
              </CBadge>
            </CCardBody>
          </CCard>
        </CCol>
      </CRow>

      {/* Service Status */}
      <CRow>
        <CCol xs={12} lg={6}>
          <CCard className="mb-4">
            <CCardHeader>
              <strong>StorageSage Service</strong>
            </CCardHeader>
            <CCardBody>
              <CListGroup flush>
                <CListGroupItem className="d-flex justify-content-between align-items-center">
                  <span>API Server</span>
                  <CBadge color={health ? 'success' : 'danger'}>
                    {health ? 'Running' : 'Offline'}
                  </CBadge>
                </CListGroupItem>
                <CListGroupItem className="d-flex justify-content-between align-items-center">
                  <span>Version</span>
                  <code>{health?.version || 'N/A'}</code>
                </CListGroupItem>
                <CListGroupItem className="d-flex justify-content-between align-items-center">
                  <span>Uptime</span>
                  <span>{formatUptime(health?.uptime_seconds)}</span>
                </CListGroupItem>
                <CListGroupItem className="d-flex justify-content-between align-items-center">
                  <span>Start Time</span>
                  <span>
                    {health?.started_at
                      ? new Date(health.started_at).toLocaleString()
                      : 'N/A'}
                  </span>
                </CListGroupItem>
              </CListGroup>
            </CCardBody>
          </CCard>
        </CCol>

        <CCol xs={12} lg={6}>
          <CCard className="mb-4">
            <CCardHeader>
              <strong>Cleanup Service</strong>
            </CCardHeader>
            <CCardBody>
              <CListGroup flush>
                <CListGroupItem className="d-flex justify-content-between align-items-center">
                  <span>Scheduler Status</span>
                  <CBadge color={metrics?.cleanup?.enabled ? 'success' : 'warning'}>
                    {metrics?.cleanup?.enabled ? 'Enabled' : 'Disabled'}
                  </CBadge>
                </CListGroupItem>
                <CListGroupItem className="d-flex justify-content-between align-items-center">
                  <span>Last Run</span>
                  <span>
                    {metrics?.cleanup?.last_run
                      ? new Date(metrics.cleanup.last_run).toLocaleString()
                      : 'Never'}
                  </span>
                </CListGroupItem>
                <CListGroupItem className="d-flex justify-content-between align-items-center">
                  <span>Next Scheduled Run</span>
                  <span>
                    {metrics?.cleanup?.next_run
                      ? new Date(metrics.cleanup.next_run).toLocaleString()
                      : 'Not scheduled'}
                  </span>
                </CListGroupItem>
                <CListGroupItem className="d-flex justify-content-between align-items-center">
                  <span>Total Runs</span>
                  <span>{metrics?.cleanup?.total_runs || 0}</span>
                </CListGroupItem>
              </CListGroup>
            </CCardBody>
          </CCard>
        </CCol>
      </CRow>

      {/* System Resources */}
      {metrics && (
        <CRow>
          <CCol xs={12} lg={6}>
            <CCard className="mb-4">
              <CCardHeader>
                <strong>Disk Status</strong>
              </CCardHeader>
              <CCardBody>
                <CListGroup flush>
                  <CListGroupItem className="d-flex justify-content-between align-items-center">
                    <span>Total Capacity</span>
                    <strong>
                      {metrics.disk?.total
                        ? `${(metrics.disk.total / (1024 ** 3)).toFixed(2)} GB`
                        : 'N/A'}
                    </strong>
                  </CListGroupItem>
                  <CListGroupItem className="d-flex justify-content-between align-items-center">
                    <span>Used Space</span>
                    <strong>
                      {metrics.disk?.used
                        ? `${(metrics.disk.used / (1024 ** 3)).toFixed(2)} GB`
                        : 'N/A'}
                    </strong>
                  </CListGroupItem>
                  <CListGroupItem className="d-flex justify-content-between align-items-center">
                    <span>Free Space</span>
                    <strong className="text-success">
                      {metrics.disk?.free
                        ? `${(metrics.disk.free / (1024 ** 3)).toFixed(2)} GB`
                        : 'N/A'}
                    </strong>
                  </CListGroupItem>
                  <CListGroupItem className="d-flex justify-content-between align-items-center">
                    <span>Usage Level</span>
                    <CBadge color={statusBadge.color}>
                      {metrics.disk?.total
                        ? `${((metrics.disk.used / metrics.disk.total) * 100).toFixed(1)}%`
                        : 'N/A'}
                    </CBadge>
                  </CListGroupItem>
                </CListGroup>
              </CCardBody>
            </CCard>
          </CCol>

          <CCol xs={12} lg={6}>
            <CCard className="mb-4">
              <CCardHeader>
                <strong>Monitoring Endpoints</strong>
              </CCardHeader>
              <CCardBody>
                <CListGroup flush>
                  <CListGroupItem>
                    <div className="d-flex justify-content-between align-items-center mb-1">
                      <span>Prometheus Metrics</span>
                      <CBadge color="success">Available</CBadge>
                    </div>
                    <code className="small">/metrics</code>
                  </CListGroupItem>
                  <CListGroupItem>
                    <div className="d-flex justify-content-between align-items-center mb-1">
                      <span>Health Check</span>
                      <CBadge color="success">Available</CBadge>
                    </div>
                    <code className="small">/health</code>
                  </CListGroupItem>
                  <CListGroupItem>
                    <div className="d-flex justify-content-between align-items-center mb-1">
                      <span>API Endpoint</span>
                      <CBadge color="success">Available</CBadge>
                    </div>
                    <code className="small">/api/*</code>
                  </CListGroupItem>
                </CListGroup>
              </CCardBody>
            </CCard>
          </CCol>
        </CRow>
      )}

      {/* Systemd Integration Info */}
      <CRow>
        <CCol xs={12}>
          <CCard className="mb-4">
            <CCardHeader>
              <strong>Systemd Integration</strong>
            </CCardHeader>
            <CCardBody>
              <p className="text-muted mb-3">
                StorageSage is designed to run as a systemd service. Use these commands to manage the service:
              </p>
              <CListGroup flush>
                <CListGroupItem>
                  <strong>Check service status:</strong>
                  <br />
                  <code>sudo systemctl status storagesage</code>
                </CListGroupItem>
                <CListGroupItem>
                  <strong>Start service:</strong>
                  <br />
                  <code>sudo systemctl start storagesage</code>
                </CListGroupItem>
                <CListGroupItem>
                  <strong>Stop service:</strong>
                  <br />
                  <code>sudo systemctl stop storagesage</code>
                </CListGroupItem>
                <CListGroupItem>
                  <strong>Restart service:</strong>
                  <br />
                  <code>sudo systemctl restart storagesage</code>
                </CListGroupItem>
                <CListGroupItem>
                  <strong>Enable on boot:</strong>
                  <br />
                  <code>sudo systemctl enable storagesage</code>
                </CListGroupItem>
                <CListGroupItem>
                  <strong>View logs:</strong>
                  <br />
                  <code>sudo journalctl -u storagesage -f</code>
                </CListGroupItem>
              </CListGroup>
            </CCardBody>
          </CCard>
        </CCol>
      </CRow>
    </>
  )
}

export default SystemHealth
