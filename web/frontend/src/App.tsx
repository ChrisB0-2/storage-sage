import { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import toast, { Toaster } from 'react-hot-toast';
import LoginPage from './pages/LoginPage';
import Dashboard from './pages/Dashboard';
import ConfigEditor from './pages/ConfigEditor';
import DeletedFilesLog from './components/DeletedFilesLog';
import SessionWarning from './components/SessionWarning';
import { authService } from './services/auth';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false);
  const [isLoading, setIsLoading] = useState<boolean>(true);

  useEffect(() => {
    // Check if user has valid token on mount (includes expiration check)
    setIsAuthenticated(authService.isAuthenticated());
    setIsLoading(false);
  }, []);

  useEffect(() => {
    if (!isAuthenticated) {
      return; // Don't check if not authenticated
    }

    // Set up periodic token expiration check
    const checkInterval = setInterval(() => {
      const isAuth = authService.isAuthenticated();
      
      if (!isAuth) {
        // Token expired
        setIsAuthenticated(false);
        toast.error('Your session has expired. Please log in again.');
        authService.logout();
      }
    }, 60000); // Check every minute

    return () => clearInterval(checkInterval);
  }, [isAuthenticated]);

  const handleLogin = async (username: string, password: string) => {
    try {
      await authService.login(username, password);
      setIsAuthenticated(true);
      toast.success('Login successful!');
      return true;
    } catch (error) {
      toast.error('Login failed. Please check your credentials.');
      return false;
    }
  };

  const handleLogout = () => {
    authService.logout();
    setIsAuthenticated(false);
    toast.success('Logged out successfully');
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-900">
        <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
      </div>
    );
  }

  return (
    <>
      <Toaster position="top-right" />
      {isAuthenticated && (
        <SessionWarning
          onExtend={() => {
            // Token refresh would go here if backend supports it
            toast.success('Session extended');
          }}
        />
      )}
      <BrowserRouter>
        <Routes>
          <Route
            path="/login"
            element={
              isAuthenticated ? (
                <Navigate to="/dashboard" replace />
              ) : (
                <LoginPage onLogin={handleLogin} />
              )
            }
          />
          <Route
            path="/dashboard"
            element={
              isAuthenticated ? (
                <Dashboard onLogout={handleLogout} />
              ) : (
                <Navigate to="/login" replace />
              )
            }
          />
          <Route
            path="/config"
            element={
              isAuthenticated ? (
                <ConfigEditor onLogout={handleLogout} />
              ) : (
                <Navigate to="/login" replace />
              )
            }
          />
          <Route
            path="/deletions"
            element={
              isAuthenticated ? (
                <DeletedFilesLog onLogout={handleLogout} />
              ) : (
                <Navigate to="/login" replace />
              )
            }
          />
          <Route path="/" element={<Navigate to="/dashboard" replace />} />
        </Routes>
      </BrowserRouter>
    </>
  );
}

export default App;
