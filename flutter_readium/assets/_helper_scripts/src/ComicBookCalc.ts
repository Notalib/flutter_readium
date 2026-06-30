import { ViewSize, type ComicKeyframe, type ComicPageSize, type ComicPanel } from './types';

// At which factor should we pane over a frame?
const panningFactor = 1.76;

// Phase durations for a panel that needs an intra-panel pan. Each is independent
// so tuning one doesn't steal time from another; together with the pan they sum
// to exactly `duration` (the audio-synced narration clip) — see makeKeyFrames.

// extra time to navigate to and settle on a big panel with intra-panel animations.
const extraFocusDuration = 100;
// duration of a plain panel-to-panel move (a panel that needs no intra-panel pan)
const panelToPanelDuration = 350;
// The first zoom from the full page into a panel (or the first panel after a page
// switch) covers a much larger scale change than adjacent panel-to-panel moves, so
// it's given more time to avoid feeling sudden. Only used when isInitialZoom is set.
const initialFocusDuration = 500;
// beat on the full panel before panning starts
const holdBeforePanningDuration = 500;
// zoom from full-panel view into the first half
const zoomIntoPanStartDuration = 300;
// Visual floor for any plain panel-to-panel move. If the narration clip is shorter than
// this we'd otherwise produce a glitch-fast move; we accept a small audio overrun instead.
// duration === 0 (instant mount / stop) is exempted from this floor.
const minPanelMoveDuration = 250;
// Minimum time we'll spend on the actual pan portion of an intra-panel pan. If a clip is
// long enough to cross the pre-pan threshold but the pan itself would be shorter than this,
// we skip the pan entirely (existing graceful fallback) rather than show a rushed pan.
const minIntraPanelPanDuration = 500;
const MAX_ZOOM_VALUE = 3;
const framePadding = 15;

export class ComicBookCalc {
  /**
   * Calculate the position and size of the full page frame.
   * This is needed for the initial zoomed out view of the comic page, where the full page is shown within the container without
   * odd flicker or unneeded animation of the image resizing.
   * @param canvasSize
   * @param availableWidth
   * @param availableHeight
   * @returns
   */
  public static calcFullPageComicFrame(canvasSize: ComicPageSize, availableWidth: number, availableHeight: number): ComicPanel {
    return this.calcFramePositionAndSize({ ...canvasSize, top: 0, left: 0 }, canvasSize, availableWidth, availableHeight);
  }

  /**
   * Make animation keyframes for a given frame and container size.
   * @param currentFrame
   * @param canvasSize
   * @param availableWidth
   * @param availableHeight
   * @param duration
   * @param isInitialZoom - true when zooming in from the full page view (first
   *   render on a page or after a page switch); uses a longer focus duration.
   * @returns
   */
  public static makeKeyFrames(
    currentFrame: ComicPanel,
    canvasSize: ComicPageSize,
    availableWidth: number,
    availableHeight: number,
    duration: number,
    isInitialZoom = false,
  ): ComicKeyframe[] {
    console.debug(`ComicBookCalc.makeKeyFrames() -> currentFrame: ${JSON.stringify(currentFrame)}, canvasSize: ${JSON.stringify(canvasSize)}, availableWidth: ${availableWidth}, availableHeight: ${availableHeight}, duration: ${duration}, isInitialZoom: ${isInitialZoom}`);
    // Determine whether this panel needs an intra-panel pan first, since that
    // decides how long the initial focus keyframe should last (see `focus` below).
    let panFramePosition: ComicPanel | undefined;
    let finalFramePosition: ComicPanel | undefined;
    if (this.shouldDoVerticalPanning(currentFrame, availableHeight)) {
      // Step 1.: Move to the top of the frame.
      panFramePosition = makeTopHalfComicFrame(currentFrame);

      // Step 2.: Pan downwards from the top of the frame to the bottom of the frame.
      // This means the top/left y coordinate end up being is frame's height - width;
      finalFramePosition = makeBottomHalfComicFrame(currentFrame);
    } else if (this.shouldDoHorizontalPanning(currentFrame, availableWidth)) {
      // Step 1. Move to the left side of the frame.
      panFramePosition = makeLeftHalfComicFrame(currentFrame);

      // Step 2. Pan leftwards from the left of the frame to the right side of the frame.
      // This means top/left x coordinate end up being frame's width - height.
      finalFramePosition = makeRightHalfComicFrame(currentFrame);
    }
    const willPan = !!panFramePosition && !!finalFramePosition;

    // Duration of the first keyframe — the move/zoom onto the target panel:
    //  - initial zoom from the full page view -> initialFocusDuration (largest move)
    //  - a panel that will pan -> focusDuration (settle on it before panning)
    //  - a plain panel-to-panel move -> panelToPanelDuration
    const focus = isInitialZoom
      ? initialFocusDuration
      : willPan ? extraFocusDuration : panelToPanelDuration;

    const focusKeyframe = this.calcFramePositionAndSize(currentFrame, canvasSize, availableWidth, availableHeight);
    // Pick the duration for the focus keyframe. Three cases:
    // - duration 0: instant render (initial mount / stop) — no animation.
    // - intra-panel pan: the 500ms hold that follows the focus keyframe is what gives
    //   the reader time to orient, so no minimum floor is needed on the focus itself.
    // - plain panel-to-panel: floor at minPanelMoveDuration so very short narration
    //   clips don't produce a glitch-fast move.
    const focusDuration = duration === 0
      ? 0
      : willPan
        ? Math.min(focus, duration)
        : Math.max(minPanelMoveDuration, Math.min(focus, duration));
    const keyframes: ComicKeyframe[] = [
      {
        ...focusKeyframe,
        duration: focusDuration,
        opacity: 1, // fixes odd jump at first render of the new image.
      },
    ];

    // Plain move (no panning) or no time budget: just the single focus keyframe.
    if (!panFramePosition || !finalFramePosition || !duration) {
      return keyframes;
    }

    // Everything before the actual pan: focus zoom + hold + zoom into the first
    // half. The pan itself fills whatever narration time is left, so the whole
    // sequence lands exactly on `duration` and the pan is never truncated.
    const prePanDuration = focus + holdBeforePanningDuration + zoomIntoPanStartDuration;

    if (duration < prePanDuration + minIntraPanelPanDuration) {
      console.warn(`ComicBookCalc.MakeKeyFrames() -> duration ${duration}ms too short for a non-rushed pan (need >= ${prePanDuration + minIntraPanelPanDuration}ms), skipping pan animation.`);
      return keyframes;
    }

    // After zooming to the frame, hold briefly so the reader can orient before panning starts.
    keyframes[0].holdDuration = holdBeforePanningDuration;

    keyframes.push(
      {
        ...this.calcFramePositionAndSize(panFramePosition, canvasSize, availableWidth, availableHeight),
        duration: zoomIntoPanStartDuration,
      },
      {
        ...this.calcFramePositionAndSize(finalFramePosition, canvasSize, availableWidth, availableHeight),
        // The pan fills the remaining narration time, so focus + hold + zoom + pan == duration.
        duration: duration - prePanDuration,
      },
    );

    return keyframes;
  }

  /**
   * Should we do vertical panning?
   *
   * Vertical panning is needed if the ratio between frame's height and width is larger than panningFactor.
   * AND
   * The frame's height is larger than the containers height * panningFactor
   */
  public static shouldDoVerticalPanning(framePosition: ComicPanel, availableHeight: number): boolean {
    return framePosition.height / framePosition.width >= panningFactor && framePosition.height > availableHeight * panningFactor;
  }

  /**
   * Should we do horizontal panning?
   *
   * Horizontal panning is needed if the ratio between frame's width and height is larger than panningFactor.
   * AND
   * The frame's width is larger than the containers width * panningFactor
   */
  public static shouldDoHorizontalPanning(framePosition: ComicPanel, availableWidth: number): boolean {
    return framePosition.width / framePosition.height >= panningFactor && framePosition.width > availableWidth * panningFactor;
  }

  public static calcScaleToFit(frame: ComicPanel, availableWidth: number, availableHeight: number): number {
    // Start by getting width and height of the container minus the padding.
    const { viewWidth, viewHeight } = this.getAvailableViewSize(availableWidth, availableHeight);

    // Destruct the framing info into size and top/left-coordinates.
    const {
      width: frameWidth,
      height: frameHeight,
    } = frame;

    return Math.min(MAX_ZOOM_VALUE, viewWidth / frameWidth, viewHeight / frameHeight);
  }

  /**
   * Get available rendering viewport. Which is the container's size minus padding.
   *
   * @param availableWidth
   * @param availableHeight
   * @returns
   */
  private static getAvailableViewSize(availableWidth: number, availableHeight: number): ViewSize {
    return {
      viewWidth: availableWidth - framePadding * 2,
      viewHeight: availableHeight - framePadding * 2,
    };
  }

  /**
   * Calculate the position and sizing info needed to show a frame within
   * the container element.
   *
   * If the frame too large to fit within the container, the image will be resized.
   */
  public static calcFramePositionAndSize(frame: ComicPanel, canvasSize: ComicPageSize, availableWidth: number, availableHeight: number): ComicPanel {
    // Start by getting width and height of the container minus the padding.
    const { viewWidth, viewHeight } = this.getAvailableViewSize(availableWidth, availableHeight);

    // Get image size info.
    const { width: imageWidth, height: imageHeight } = canvasSize;

    // Destruct the framing info into size and top/left-coordinates.
    const {
      width: frameWidth,
      height: frameHeight,
      top: frameY0,
      left: frameX0,
    } = frame;

    // Calculate the scale factor needed to fit the frame within the container.
    const scaleFactor = this.calcScaleToFit(frame, availableWidth, availableHeight);

    // Resize the image if needed
    const scaledImageWidth = imageWidth * scaleFactor;
    const scaledImageHeight = imageHeight * scaleFactor;

    // Scaled top/left coordinates are a result of the original coordinate * scaleFactor.
    const scaledFrameX0 = -(frameX0 * scaleFactor);
    const scaledFrameY0 = -(frameY0 * scaleFactor);

    // The frame needs to be centered, if the scaled frame size is smaller than the container size.
    const scaledFrameWidth = frameWidth * scaleFactor;
    const scaledFrameHeight = frameHeight * scaleFactor;

    // Centering is done by calculating the difference between the container size and the scaled frame size, and dividing it by 2 to get the centering offset.
    const xCentering = (viewWidth - scaledFrameWidth) / 2;
    const yCentering = (viewHeight - scaledFrameHeight) / 2;

    // Final top/left coordinates are a result of the scaled frame coordinates plus the centering offset.
    const scaledTopOffset = yCentering + scaledFrameY0 + framePadding;
    const scaledLeftOffset = xCentering + scaledFrameX0 + framePadding;

    return {
      top: scaledTopOffset,
      left: scaledLeftOffset,
      width: scaledImageWidth,
      height: scaledImageHeight,
    };
  }
}

/**
 * Make a comic frame that is the top half of the original frame.
 * This is used as the starting position for vertical panning, where we start at the top of the frame and pan downwards to the bottom of the frame.
 * @param frame
 * @returns
 */
function makeTopHalfComicFrame(frame: ComicPanel): ComicPanel {
  return {
    ...frame,
    height: frame.width,
  };
}

/**
 * Make a comic frame that is the bottom half of the original frame.
 * This is used as the ending position for vertical panning, where we start at the top of the frame and pan to the bottom of the frame.
 * The top/left y coordinate end up being is frame's height - width.
 * @param frame
 * @returns
 */
function makeBottomHalfComicFrame(frame: ComicPanel): ComicPanel {
  return {
    ...makeTopHalfComicFrame(frame),
    top: frame.top + frame.height - frame.width + framePadding,
  }
}

/**
 * Make a comic frame that is the left half of the original frame.
 * This is used as the starting position for horizontal panning, where we start at the left of the frame and pan to the right side of the frame.
 * @param frame
 * @returns
 */
function makeLeftHalfComicFrame(frame: ComicPanel): ComicPanel {
  return {
    ...frame,
    width: frame.height,
  };
}

/**
 * Make a comic frame that is the right half of the original frame.
 * This is used as the ending position for horizontal panning, where we start at the left of the frame and pan to the right side of the frame.
 * The top/left x coordinate end up being frame's width - height.
 * @param frame
 * @returns
 */
function makeRightHalfComicFrame(frame: ComicPanel): ComicPanel {
  return {
    ...makeLeftHalfComicFrame(frame),
    left: frame.left + frame.width - frame.height + framePadding,
  }
}
