import React, { useState, useEffect } from 'react'
import {
  CCard,
  CCardBody,
  CCardHeader,
  CCol,
  CRow,
  CProgress,
  CProgressBar,
  CButton,
  CSpinner,
  CAlert,
} from '@coreui/react'
import CIcon from '@coreui/icons-react'
import { cilReload, cilCloudDownload } from '@coreui/icons'
import { getMetrics, triggerCleanup } from '../../api/storageSageClient'

const Overview = () => {
  const [metrics, setMetrics] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [cleanupRunning, setCleanupRunning] = useState(false)
  const [lastUpdate, setLastUpdate] = useState(null)

  const fetchMetrics = async () => {
    try {
      setLoading(true)
      setError(null)
      const data = await getMetrics()
      setMetrics(data)
      setLastUpdate(new Date())
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleCleanup = async () => {
    try {
      setCleanupRunning(true)
      setError(null)
      await triggerCleanup()
      // Refresh metrics after cleanup
      setTimeout(fetchMetrics, 1000)
    } catch (err) {
      setError(`Cleanup failed: ${err.message}`)
    } finally {
      setCleanupRunning(false)
    }
  }

  useEffect(() => {
    fetchMetrics()
    // Auto-refresh every 30 seconds
    const interval = setInterval(fetchMetrics, 30000)
    return () => clearInterval(interval)
  }, [])

  const formatBytes = (bytes) => {
    if (!bytes) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`
  }

  const calculateUsagePercent = () => {
    if (!metrics?.disk) return 0
    return ((metrics.disk.used / metrics.disk.total) * 100).toFixed(1)
  }

  const getProgressColor = (percent) => {
    if (percent >= 90) return 'danger'
    if (percent >= 75) return 'warning'
    return 'success'
  }

  if (loading && !metrics) {
    return (
      <div className="text-center">
        <CSpinner color="primary" />
        <p className="mt-2">Loading metrics...</p>
      </div>
    )
  }

  return (
    <>
      <CRow>
        <CCol xs={12}>
          <CCard className="mb-4">
            <CCardHeader className="d-flex justify-content-between align-items-center">
              <strong>StorageSage Dashboard</strong>
              <div>
                <CButton
                  color="primary"
                  size="sm"
                  onClick={fetchMetrics}
                  disabled={loading}
                  className="me-2"
                >
                  <CIcon icon={cilReload} className="me-1" />
                  Refresh
                </CButton>
                <CButton
                  color="success"
                  size="sm"
                  onClick={handleCleanup}
                  disabled={cleanupRunning}
                >
                  <CIcon icon={cilCloudDownload} className="me-1" />
                  {cleanupRunning ? 'Running...' : 'Run Cleanup'}
                </CButton>
              </div>
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

      {metrics && (
        <>
          {/* Disk Usage Overview */}
          <CRow>
            <CCol xs={12} md={6} xl={3}>
              <CCard className="mb-4">
                <CCardBody>
                  <div className="text-muted small text-uppercase fw-semibold">Total Space</div>
                  <div className="fs-4 fw-semibold">{formatBytes(metrics.disk?.total)}</div>
                </CCardBody>
              </CCard>
            </CCol>
            <CCol xs={12} md={6} xl={3}>
              <CCard className="mb-4">
                <CCardBody>
                  <div className="text-muted small text-uppercase fw-semibold">Used Space</div>
                  <div className="fs-4 fw-semibold">{formatBytes(metrics.disk?.used)}</div>
                </CCardBody>
              </CCard>
            </CCol>
            <CCol xs={12} md={6} xl={3}>
              <CCard className="mb-4">
                <CCardBody>
                  <div className="text-muted small text-uppercase fw-semibold">Free Space</div>
                  <div className="fs-4 fw-semibold text-success">
                    {formatBytes(metrics.disk?.free)}
                  </div>
                </CCardBody>
              </CCard>
            </CCol>
            <CCol xs={12} md={6} xl={3}>
              <CCard className="mb-4">
                <CCardBody>
                  <div className="text-muted small text-uppercase fw-semibold">Usage</div>
                  <div className={`fs-4 fw-semibold text-${getProgressColor(calculateUsagePercent())}`}>
                    {calculateUsagePercent()}%
                  </div>
                </CCardBody>
              </CCard>
            </CCol>
          </CRow>

          {/* Disk Usage Progress */}
          <CRow>
            <CCol xs={12}>
              <CCard className="mb-4">
                <CCardHeader>
                  <strong>Disk Usage</strong>
                </CCardHeader>
                <CCardBody>
                  <CProgress height={30} className="mb-3">
                    <CProgressBar
                      color={getProgressColor(calculateUsagePercent())}
                      value={calculateUsagePercent()}
                    >
                      {calculateUsagePercent()}% Used
                    </CProgressBar>
                  </CProgress>
                  <div className="d-flex justify-content-between text-muted small">
                    <span>Used: {formatBytes(metrics.disk?.used)}</span>
                    <span>Free: {formatBytes(metrics.disk?.free)}</span>
                    <span>Total: {formatBytes(metrics.disk?.total)}</span>
                  </div>
                </CCardBody>
              </CCard>
            </CCol>
          </CRow>

          {/* Cleanup Statistics */}
          <CRow>
            <CCol xs={12} lg={6}>
              <CCard className="mb-4">
                <CCardHeader>
                  <strong>Cleanup Statistics</strong>
                </CCardHeader>
                <CCardBody>
                  <div className="mb-3">
                    <div className="d-flex justify-content-between">
                      <span className="text-muted">Total Files Deleted</span>
                      <strong>{metrics.cleanup?.total_deletions || 0}</strong>
                    </div>
                  </div>
                  <div className="mb-3">
                    <div className="d-flex justify-content-between">
                      <span className="text-muted">Space Recovered</span>
                      <strong className="text-success">
                        {formatBytes(metrics.cleanup?.space_freed)}
                      </strong>
                    </div>
                  </div>
                  <div className="mb-3">
                    <div className="d-flex justify-content-between">
                      <span className="text-muted">Last Cleanup</span>
                      <strong>
                        {metrics.cleanup?.last_run
                          ? new Date(metrics.cleanup.last_run).toLocaleString()
                          : 'Never'}
                      </strong>
                    </div>
                  </div>
                  <div>
                    <div className="d-flex justify-content-between">
                      <span className="text-muted">Next Scheduled Run</span>
                      <strong>
                        {metrics.cleanup?.next_run
                          ? new Date(metrics.cleanup.next_run).toLocaleString()
                          : 'Not scheduled'}
                      </strong>
                    </div>
                  </div>
                </CCardBody>
              </CCard>
            </CCol>

            <CCol xs={12} lg={6}>
              <CCard className="mb-4">
                <CCardHeader>
                  <strong>System Thresholds</strong>
                </CCardHeader>
                <CCardBody>
                  <div className="mb-3">
                    <div className="d-flex justify-content-between mb-1">
                      <span className="text-muted">Warning Threshold</span>
                      <strong>{metrics.thresholds?.warning_percent || 0}%</strong>
                    </div>
                    <CProgress height={10}>
                      <CProgressBar color="warning" value={metrics.thresholds?.warning_percent || 0} />
                    </CProgress>
                  </div>
                  <div className="mb-3">
                    <div className="d-flex justify-content-between mb-1">
                      <span className="text-muted">Critical Threshold</span>
                      <strong>{metrics.thresholds?.critical_percent || 0}%</strong>
                    </div>
                    <CProgress height={10}>
                      <CProgressBar color="danger" value={metrics.thresholds?.critical_percent || 0} />
                    </CProgress>
                  </div>
                  <div>
                    <div className="d-flex justify-content-between">
                      <span className="text-muted">Current Status</span>
                      <strong className={`text-${getProgressColor(calculateUsagePercent())}`}>
                        {calculateUsagePercent() >= (metrics.thresholds?.critical_percent || 90)
                          ? 'CRITICAL'
                          : calculateUsagePercent() >= (metrics.thresholds?.warning_percent || 75)
                          ? 'WARNING'
                          : 'HEALTHY'}
                      </strong>
                    </div>
                  </div>
                </CCardBody>
              </CCard>
            </CCol>
          </CRow>
        </>
      )}
    </>
  )
}

export default Overview
