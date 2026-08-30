import { getCurrentWindow } from '@tauri-apps/api/window';
import type { MouseEvent as ReactMouseEvent } from 'react';

const INTERACTIVE_SELECTOR = [
  'button',
  'input',
  'select',
  'textarea',
  'a',
  '[role="button"]',
  '[contenteditable="true"]',
  '[data-tauri-no-drag]',
].join(',');

/**
 * Start a native Tauri window drag from a React mouse event.
 *
 * WKWebView does not consistently honour Chromium's `-webkit-app-region`
 * implementation. Calling Tauri's native API from the user gesture keeps
 * frameless windows draggable on macOS while preserving normal controls.
 */
export function startWindowDrag(event: ReactMouseEvent<HTMLElement>): void {
  if (event.button !== 0 || event.defaultPrevented) return;

  const target = event.target;
  if (target instanceof Element && target.closest(INTERACTIVE_SELECTOR)) return;

  event.preventDefault();
  void getCurrentWindow()
    .startDragging()
    .catch((error) => {
      console.warn('Unable to start native window drag:', error);
    });
}
