import React, { useState, useEffect } from 'react'
import {
  CCard,
  CCardBody,
  CCardHeader,
  CCol,
  CRow,
  CForm,
  CFormInput,
  CFormLabel,
  CFormSelect,
  CButton,
  CSpinner,
  CAlert,
  CTable,
  CTableHead,
  CTableBody,
  CTableRow,
  CTableHeaderCell,
  CTableDataCell,
  CModal,
  CModalHeader,
  CModalTitle,
  CModalBody,
  CModalFooter,
} from '@coreui/react'
import CIcon from '@coreui/icons-react'
import { cilPlus, cilTrash, cilPencil, cilSave } from '@coreui/icons'
import { getConfig, updateConfig } from '../../api/storageSageClient'

const CleanupRules = () => {
  const [config, setConfig] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)
  const [showModal, setShowModal] = useState(false)
  const [editingRule, setEditingRule] = useState(null)
  const [editingIndex, setEditingIndex] = useState(null)

  // Form state for new/editing rule
  const [ruleForm, setRuleForm] = useState({
    path: '',
    max_age_days: 30,
    min_size_mb: 0,
    pattern: '*',
  })

  const fetchConfig = async () => {
    try {
      setLoading(true)
      setError(null)
      const data = await getConfig()
      setConfig(data)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleSaveConfig = async () => {
    try {
      setSaving(true)
      setError(null)
      setSuccess(null)
      await updateConfig(config)
      setSuccess('Configuration saved successfully!')
      setTimeout(() => setSuccess(null), 3000)
    } catch (err) {
      setError(`Failed to save config: ${err.message}`)
    } finally {
      setSaving(false)
    }
  }

  const handleGlobalChange = (field, value) => {
    setConfig({
      ...config,
      global: {
        ...config.global,
        [field]: value,
      },
    })
  }

  const handleAddRule = () => {
    setEditingRule(null)
    setEditingIndex(null)
    setRuleForm({
      path: '',
      max_age_days: 30,
      min_size_mb: 0,
      pattern: '*',
    })
    setShowModal(true)
  }

  const handleEditRule = (rule, index) => {
    setEditingRule(rule)
    setEditingIndex(index)
    setRuleForm({ ...rule })
    setShowModal(true)
  }

  const handleDeleteRule = (index) => {
    const newRules = [...(config.per_path_rules || [])]
    newRules.splice(index, 1)
    setConfig({
      ...config,
      per_path_rules: newRules,
    })
  }

  const handleSaveRule = () => {
    const newRules = [...(config.per_path_rules || [])]
    if (editingIndex !== null) {
      newRules[editingIndex] = ruleForm
    } else {
      newRules.push(ruleForm)
    }
    setConfig({
      ...config,
      per_path_rules: newRules,
    })
    setShowModal(false)
  }

  useEffect(() => {
    fetchConfig()
  }, [])

  if (loading && !config) {
    return (
      <div className="text-center">
        <CSpinner color="primary" />
        <p className="mt-2">Loading configuration...</p>
      </div>
    )
  }

  return (
    <>
      <CRow>
        <CCol xs={12}>
          <CCard className="mb-4">
            <CCardHeader className="d-flex justify-content-between align-items-center">
              <strong>Cleanup Rules Configuration</strong>
              <CButton
                color="success"
                size="sm"
                onClick={handleSaveConfig}
                disabled={saving || !config}
              >
                <CIcon icon={cilSave} className="me-1" />
                {saving ? 'Saving...' : 'Save Configuration'}
              </CButton>
            </CCardHeader>
            <CCardBody>
              {error && (
                <CAlert color="danger" dismissible onClose={() => setError(null)}>
                  {error}
                </CAlert>
              )}
              {success && (
                <CAlert color="success" dismissible onClose={() => setSuccess(null)}>
                  {success}
                </CAlert>
              )}
            </CCardBody>
          </CCard>
        </CCol>
      </CRow>

      {config && (
        <>
          {/* Global Settings */}
          <CRow>
            <CCol xs={12}>
              <CCard className="mb-4">
                <CCardHeader>
                  <strong>Global Settings</strong>
                </CCardHeader>
                <CCardBody>
                  <CForm>
                    <CRow className="mb-3">
                      <CCol md={6}>
                        <CFormLabel htmlFor="maxAgeDays">Default Max Age (days)</CFormLabel>
                        <CFormInput
                          type="number"
                          id="maxAgeDays"
                          value={config.global?.max_age_days || 30}
                          onChange={(e) =>
                            handleGlobalChange('max_age_days', parseInt(e.target.value))
                          }
                          min="1"
                        />
                        <small className="text-muted">
                          Delete files older than this many days
                        </small>
                      </CCol>
                      <CCol md={6}>
                        <CFormLabel htmlFor="minSizeMB">Minimum File Size (MB)</CFormLabel>
                        <CFormInput
                          type="number"
                          id="minSizeMB"
                          value={config.global?.min_size_mb || 0}
                          onChange={(e) =>
                            handleGlobalChange('min_size_mb', parseInt(e.target.value))
                          }
                          min="0"
                        />
                        <small className="text-muted">
                          Only consider files larger than this size
                        </small>
                      </CCol>
                    </CRow>
                    <CRow className="mb-3">
                      <CCol md={6}>
                        <CFormLabel htmlFor="warningThreshold">Warning Threshold (%)</CFormLabel>
                        <CFormInput
                          type="number"
                          id="warningThreshold"
                          value={config.global?.warning_threshold || 75}
                          onChange={(e) =>
                            handleGlobalChange('warning_threshold', parseInt(e.target.value))
                          }
                          min="0"
                          max="100"
                        />
                      </CCol>
                      <CCol md={6}>
                        <CFormLabel htmlFor="criticalThreshold">Critical Threshold (%)</CFormLabel>
                        <CFormInput
                          type="number"
                          id="criticalThreshold"
                          value={config.global?.critical_threshold || 90}
                          onChange={(e) =>
                            handleGlobalChange('critical_threshold', parseInt(e.target.value))
                          }
                          min="0"
                          max="100"
                        />
                      </CCol>
                    </CRow>
                    <CRow>
                      <CCol md={12}>
                        <CFormLabel htmlFor="cleanupSchedule">Cleanup Schedule (cron)</CFormLabel>
                        <CFormInput
                          type="text"
                          id="cleanupSchedule"
                          value={config.global?.schedule || '0 2 * * *'}
                          onChange={(e) => handleGlobalChange('schedule', e.target.value)}
                          placeholder="0 2 * * *"
                        />
                        <small className="text-muted">
                          Cron expression for automatic cleanup schedule (default: 2 AM daily)
                        </small>
                      </CCol>
                    </CRow>
                  </CForm>
                </CCardBody>
              </CCard>
            </CCol>
          </CRow>

          {/* Per-Path Rules */}
          <CRow>
            <CCol xs={12}>
              <CCard className="mb-4">
                <CCardHeader className="d-flex justify-content-between align-items-center">
                  <strong>Per-Path Rules</strong>
                  <CButton color="primary" size="sm" onClick={handleAddRule}>
                    <CIcon icon={cilPlus} className="me-1" />
                    Add Rule
                  </CButton>
                </CCardHeader>
                <CCardBody>
                  {(!config.per_path_rules || config.per_path_rules.length === 0) ? (
                    <p className="text-muted">
                      No per-path rules defined. Click "Add Rule" to create one.
                    </p>
                  ) : (
                    <CTable hover responsive>
                      <CTableHead>
                        <CTableRow>
                          <CTableHeaderCell>Path</CTableHeaderCell>
                          <CTableHeaderCell>Max Age (days)</CTableHeaderCell>
                          <CTableHeaderCell>Min Size (MB)</CTableHeaderCell>
                          <CTableHeaderCell>Pattern</CTableHeaderCell>
                          <CTableHeaderCell>Actions</CTableHeaderCell>
                        </CTableRow>
                      </CTableHead>
                      <CTableBody>
                        {config.per_path_rules.map((rule, index) => (
                          <CTableRow key={index}>
                            <CTableDataCell>
                              <code>{rule.path}</code>
                            </CTableDataCell>
                            <CTableDataCell>{rule.max_age_days}</CTableDataCell>
                            <CTableDataCell>{rule.min_size_mb}</CTableDataCell>
                            <CTableDataCell>
                              <code>{rule.pattern}</code>
                            </CTableDataCell>
                            <CTableDataCell>
                              <CButton
                                color="info"
                                size="sm"
                                className="me-2"
                                onClick={() => handleEditRule(rule, index)}
                              >
                                <CIcon icon={cilPencil} />
                              </CButton>
                              <CButton
                                color="danger"
                                size="sm"
                                onClick={() => handleDeleteRule(index)}
                              >
                                <CIcon icon={cilTrash} />
                              </CButton>
                            </CTableDataCell>
                          </CTableRow>
                        ))}
                      </CTableBody>
                    </CTable>
                  )}
                </CCardBody>
              </CCard>
            </CCol>
          </CRow>
        </>
      )}

      {/* Add/Edit Rule Modal */}
      <CModal visible={showModal} onClose={() => setShowModal(false)}>
        <CModalHeader>
          <CModalTitle>{editingRule ? 'Edit Rule' : 'Add New Rule'}</CModalTitle>
        </CModalHeader>
        <CModalBody>
          <CForm>
            <div className="mb-3">
              <CFormLabel htmlFor="rulePath">Path</CFormLabel>
              <CFormInput
                type="text"
                id="rulePath"
                value={ruleForm.path}
                onChange={(e) => setRuleForm({ ...ruleForm, path: e.target.value })}
                placeholder="/path/to/directory"
              />
            </div>
            <div className="mb-3">
              <CFormLabel htmlFor="ruleMaxAge">Max Age (days)</CFormLabel>
              <CFormInput
                type="number"
                id="ruleMaxAge"
                value={ruleForm.max_age_days}
                onChange={(e) =>
                  setRuleForm({ ...ruleForm, max_age_days: parseInt(e.target.value) })
                }
                min="1"
              />
            </div>
            <div className="mb-3">
              <CFormLabel htmlFor="ruleMinSize">Min Size (MB)</CFormLabel>
              <CFormInput
                type="number"
                id="ruleMinSize"
                value={ruleForm.min_size_mb}
                onChange={(e) =>
                  setRuleForm({ ...ruleForm, min_size_mb: parseInt(e.target.value) })
                }
                min="0"
              />
            </div>
            <div className="mb-3">
              <CFormLabel htmlFor="rulePattern">File Pattern</CFormLabel>
              <CFormInput
                type="text"
                id="rulePattern"
                value={ruleForm.pattern}
                onChange={(e) => setRuleForm({ ...ruleForm, pattern: e.target.value })}
                placeholder="*.log"
              />
              <small className="text-muted">Glob pattern (e.g., *.log, *.tmp, *)</small>
            </div>
          </CForm>
        </CModalBody>
        <CModalFooter>
          <CButton color="secondary" onClick={() => setShowModal(false)}>
            Cancel
          </CButton>
          <CButton color="primary" onClick={handleSaveRule}>
            Save Rule
          </CButton>
        </CModalFooter>
      </CModal>
    </>
  )
}

export default CleanupRules
