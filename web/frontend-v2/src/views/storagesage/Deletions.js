import React, { useState, useEffect } from 'react'
import {
  CCard,
  CCardBody,
  CCardHeader,
  CCol,
  CRow,
  CTable,
  CTableHead,
  CTableBody,
  CTableRow,
  CTableHeaderCell,
  CTableDataCell,
  CSpinner,
  CAlert,
  CButton,
  CFormSelect,
  CPagination,
  CPaginationItem,
  CBadge,
} from '@coreui/react'
import CIcon from '@coreui/icons-react'
import { cilReload } from '@coreui/icons'
import { getDeletions } from '../../api/storageSageClient'

const Deletions = () => {
  const [deletions, setDeletions] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [limit, setLimit] = useState(100)
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage] = useState(20)

  const fetchDeletions = async () => {
    try {
      setLoading(true)
      setError(null)
      const data = await getDeletions(limit)
      setDeletions(Array.isArray(data) ? data : data.deletions || [])
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchDeletions()
  }, [limit])

  const formatBytes = (bytes) => {
    if (!bytes) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`
  }

  const formatDate = (timestamp) => {
    if (!timestamp) return 'N/A'
    return new Date(timestamp).toLocaleString()
  }

  const getReasonBadge = (reason) => {
    const badges = {
      age: 'warning',
      size: 'info',
      pattern: 'primary',
      manual: 'success',
      threshold: 'danger',
    }
    return badges[reason] || 'secondary'
  }

  // Pagination
  const indexOfLastItem = currentPage * itemsPerPage
  const indexOfFirstItem = indexOfLastItem - itemsPerPage
  const currentItems = deletions.slice(indexOfFirstItem, indexOfLastItem)
  const totalPages = Math.ceil(deletions.length / itemsPerPage)

  const handlePageChange = (page) => {
    setCurrentPage(page)
  }

  if (loading && deletions.length === 0) {
    return (
      <div className="text-center">
        <CSpinner color="primary" />
        <p className="mt-2">Loading deletion history...</p>
      </div>
    )
  }

  return (
    <>
      <CRow>
        <CCol xs={12}>
          <CCard className="mb-4">
            <CCardHeader className="d-flex justify-content-between align-items-center">
              <strong>Deletion History</strong>
              <div className="d-flex align-items-center">
                <CFormSelect
                  size="sm"
                  value={limit}
                  onChange={(e) => setLimit(parseInt(e.target.value))}
                  className="me-2"
                  style={{ width: '150px' }}
                >
                  <option value={50}>Last 50</option>
                  <option value={100}>Last 100</option>
                  <option value={250}>Last 250</option>
                  <option value={500}>Last 500</option>
                  <option value={1000}>Last 1000</option>
                </CFormSelect>
                <CButton color="primary" size="sm" onClick={fetchDeletions} disabled={loading}>
                  <CIcon icon={cilReload} className="me-1" />
                  Refresh
                </CButton>
              </div>
            </CCardHeader>
            <CCardBody>
              {error && (
                <CAlert color="danger" dismissible onClose={() => setError(null)}>
                  {error}
                </CAlert>
              )}

              {deletions.length === 0 ? (
                <p className="text-muted text-center">No deletion records found.</p>
              ) : (
                <>
                  <div className="mb-3">
                    <small className="text-muted">
                      Showing {indexOfFirstItem + 1} to{' '}
                      {Math.min(indexOfLastItem, deletions.length)} of {deletions.length} records
                    </small>
                  </div>

                  <CTable hover responsive striped>
                    <CTableHead>
                      <CTableRow>
                        <CTableHeaderCell>#</CTableHeaderCell>
                        <CTableHeaderCell>File Path</CTableHeaderCell>
                        <CTableHeaderCell>Size</CTableHeaderCell>
                        <CTableHeaderCell>Deleted At</CTableHeaderCell>
                        <CTableHeaderCell>Reason</CTableHeaderCell>
                        <CTableHeaderCell>Age (days)</CTableHeaderCell>
                      </CTableRow>
                    </CTableHead>
                    <CTableBody>
                      {currentItems.map((deletion, index) => (
                        <CTableRow key={indexOfFirstItem + index}>
                          <CTableDataCell>{indexOfFirstItem + index + 1}</CTableDataCell>
                          <CTableDataCell>
                            <code className="small">{deletion.path || deletion.file_path}</code>
                          </CTableDataCell>
                          <CTableDataCell>{formatBytes(deletion.size)}</CTableDataCell>
                          <CTableDataCell>
                            {formatDate(deletion.deleted_at || deletion.timestamp)}
                          </CTableDataCell>
                          <CTableDataCell>
                            <CBadge color={getReasonBadge(deletion.reason)}>
                              {deletion.reason || 'unknown'}
                            </CBadge>
                          </CTableDataCell>
                          <CTableDataCell>
                            {deletion.age_days !== undefined ? deletion.age_days : 'N/A'}
                          </CTableDataCell>
                        </CTableRow>
                      ))}
                    </CTableBody>
                  </CTable>

                  {totalPages > 1 && (
                    <CPagination align="center" aria-label="Deletion history pagination">
                      <CPaginationItem
                        disabled={currentPage === 1}
                        onClick={() => handlePageChange(currentPage - 1)}
                      >
                        Previous
                      </CPaginationItem>

                      {[...Array(totalPages)].map((_, i) => {
                        const page = i + 1
                        // Show first 2, last 2, and pages around current
                        if (
                          page === 1 ||
                          page === totalPages ||
                          (page >= currentPage - 1 && page <= currentPage + 1)
                        ) {
                          return (
                            <CPaginationItem
                              key={page}
                              active={page === currentPage}
                              onClick={() => handlePageChange(page)}
                            >
                              {page}
                            </CPaginationItem>
                          )
                        } else if (page === currentPage - 2 || page === currentPage + 2) {
                          return <CPaginationItem key={page} disabled>...</CPaginationItem>
                        }
                        return null
                      })}

                      <CPaginationItem
                        disabled={currentPage === totalPages}
                        onClick={() => handlePageChange(currentPage + 1)}
                      >
                        Next
                      </CPaginationItem>
                    </CPagination>
                  )}
                </>
              )}
            </CCardBody>
          </CCard>
        </CCol>
      </CRow>

      {/* Summary Statistics */}
      {deletions.length > 0 && (
        <CRow>
          <CCol xs={12} md={4}>
            <CCard className="mb-4">
              <CCardBody>
                <div className="text-muted small text-uppercase fw-semibold">Total Deletions</div>
                <div className="fs-4 fw-semibold">{deletions.length}</div>
              </CCardBody>
            </CCard>
          </CCol>
          <CCol xs={12} md={4}>
            <CCard className="mb-4">
              <CCardBody>
                <div className="text-muted small text-uppercase fw-semibold">Total Space Freed</div>
                <div className="fs-4 fw-semibold text-success">
                  {formatBytes(deletions.reduce((sum, d) => sum + (d.size || 0), 0))}
                </div>
              </CCardBody>
            </CCard>
          </CCol>
          <CCol xs={12} md={4}>
            <CCard className="mb-4">
              <CCardBody>
                <div className="text-muted small text-uppercase fw-semibold">Average File Size</div>
                <div className="fs-4 fw-semibold">
                  {formatBytes(
                    deletions.reduce((sum, d) => sum + (d.size || 0), 0) / deletions.length
                  )}
                </div>
              </CCardBody>
            </CCard>
          </CCol>
        </CRow>
      )}
    </>
  )
}

export default Deletions
