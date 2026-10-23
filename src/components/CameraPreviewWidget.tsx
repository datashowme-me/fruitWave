import React, { useState } from 'react';
import { Camera, Eye, EyeOff, Hand, RefreshCw } from 'lucide-react';
import { CameraMotionTracker } from '../vision/CameraMotionTracker';

interface CameraPreviewWidgetProps {
  videoRef: React.RefObject<HTMLVideoElement | null>;
  motionTracker: CameraMotionTracker;
  cameraActive: boolean;
  onToggleCamera: () => void;
  mirror: boolean;
  onToggleMirror: () => void;
}

export const CameraPreviewWidget: React.FC<CameraPreviewWidgetProps> = ({
  videoRef,
  motionTracker,
  cameraActive,
  onToggleCamera,
  mirror,
  onToggleMirror,
}) => {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <div className="fixed bottom-6 right-6 z-30 flex flex-col items-end pointer-events-auto">
      {/* Header / Collapse Bar */}
      <div className="flex items-center gap-2 mb-2 bg-slate-900/90 backdrop-blur-md px-3 py-1.5 rounded-full border border-slate-700/60 shadow-lg text-xs font-semibold text-slate-300">
        <span className="flex items-center gap-1.5">
          <span
            className={`w-2 h-2 rounded-full ${
              cameraActive ? 'bg-emerald-500 animate-pulse' : 'bg-rose-500'
            }`}
          />
          {cameraActive ? '体感摄像头 (Vision)' : '体感已关闭'}
        </span>

        <button
          onClick={onToggleCamera}
          className="hover:text-white p-1 transition-colors"
          title={cameraActive ? '关闭摄像头' : '开启摄像头'}
        >
          <Camera className="w-3.5 h-3.5" />
        </button>

        {cameraActive && (
          <button
            onClick={onToggleMirror}
            className="hover:text-white p-1 transition-colors"
            title="镜像翻转"
          >
            <RefreshCw className="w-3.5 h-3.5" />
          </button>
        )}

        <button
          onClick={() => setCollapsed(!collapsed)}
          className="hover:text-white p-1 transition-colors"
          title={collapsed ? '展开预览' : '折叠预览'}
        >
          {collapsed ? <Eye className="w-3.5 h-3.5" /> : <EyeOff className="w-3.5 h-3.5" />}
        </button>
      </div>

      {/* Video Container */}
      {!collapsed && cameraActive && (
        <div className="relative w-48 sm:w-56 h-36 bg-black rounded-2xl overflow-hidden border-2 border-slate-700/80 shadow-2xl shadow-cyan-900/20 group">
          <video
            ref={videoRef}
            playsInline
            muted
            className={`w-full h-full object-cover ${mirror ? '-scale-x-100' : ''}`}
          />

          {/* Subdued overlay showing active motion zone */}
          <div className="absolute inset-0 pointer-events-none border border-cyan-500/20 rounded-2xl">
            {/* Guide crosshair */}
            <div className="absolute inset-0 flex items-center justify-center opacity-30">
              <div className="w-8 h-8 border border-dashed border-cyan-400 rounded-full" />
            </div>

            {/* Hand wave indicator tip */}
            <div className="absolute bottom-2 left-2 right-2 flex justify-between items-center text-[10px] text-cyan-300/80 bg-black/60 px-2 py-0.5 rounded-md backdrop-blur-xs">
              <span className="flex items-center gap-1">
                <Hand className="w-3 h-3" />
                挥手即可起刀
              </span>
              <span>1€ Filter</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
