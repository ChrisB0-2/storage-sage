/**
 * SessionWarning Component
 * Displays a warning when the user's session is about to expire
 */

import { useEffect, useState } from 'react';
import { ExclamationTriangleIcon, XMarkIcon } from '@heroicons/react/24/outline';
import { authService } from '../services/auth';

interface SessionWarningProps {
  onDismiss?: () => void;
  onExtend?: () => void;
}

export default function SessionWarning({ onDismiss, onExtend }: SessionWarningProps) {
  const [timeRemaining, setTimeRemaining] = useState<number | null>(null);
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    const checkSession = () => {
      if (authService.shouldShowSessionWarning()) {
        const timeUntil = authService.getTimeUntilExpiry();
        setTimeRemaining(timeUntil);
        setIsVisible(true);
      } else {
        setIsVisible(false);
      }
    };

    // Check immediately
    checkSession();

    // Check every 30 seconds
    const interval = setInterval(checkSession, 30000);

    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (isVisible && timeRemaining !== null) {
      // Update time remaining every second
      const updateInterval = setInterval(() => {
        const timeUntil = authService.getTimeUntilExpiry();
        if (timeUntil !== null && timeUntil > 0) {
          setTimeRemaining(timeUntil);
        } else {
          setIsVisible(false);
        }
      }, 1000);

      return () => clearInterval(updateInterval);
    }
  }, [isVisible, timeRemaining]);

  const formatTime = (ms: number): string => {
    const minutes = Math.floor(ms / 60000);
    const seconds = Math.floor((ms % 60000) / 1000);
    
    if (minutes > 0) {
      return `${minutes}m ${seconds}s`;
    }
    return `${seconds}s`;
  };

  const handleDismiss = () => {
    setIsVisible(false);
    onDismiss?.();
  };

  if (!isVisible || timeRemaining === null) {
    return null;
  }

  return (
    <div className="fixed bottom-4 right-4 z-50 max-w-md">
      <div className="bg-yellow-900 border border-yellow-700 rounded-lg shadow-lg p-4">
        <div className="flex items-start">
          <div className="flex-shrink-0">
            <ExclamationTriangleIcon className="h-5 w-5 text-yellow-400" />
          </div>
          <div className="ml-3 flex-1">
            <h3 className="text-sm font-medium text-yellow-200">
              Session Expiring Soon
            </h3>
            <div className="mt-2 text-sm text-yellow-300">
              <p>
                Your session will expire in{' '}
                <span className="font-semibold">{formatTime(timeRemaining)}</span>.
                Please save your work.
              </p>
            </div>
            {onExtend && (
              <div className="mt-4">
                <button
                  type="button"
                  onClick={onExtend}
                  className="text-sm font-medium text-yellow-200 hover:text-yellow-100 underline"
                >
                  Extend session
                </button>
              </div>
            )}
          </div>
          <div className="ml-4 flex-shrink-0">
            <button
              type="button"
              onClick={handleDismiss}
              className="inline-flex text-yellow-400 hover:text-yellow-300 focus:outline-none"
            >
              <span className="sr-only">Dismiss</span>
              <XMarkIcon className="h-5 w-5" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

