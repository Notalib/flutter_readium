import { type AnimeAnimParams } from 'animejs';
import { ViewSize, type ComicPageSize, type ComicPanel } from './types';

// At which factor should we pane over a frame?
const panningFactor = 1.75;
const focusDuration = 500;
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
   * @returns
   */
  public static makeKeyFrames(
    currentFrame: ComicPanel,
    canvasSize: ComicPageSize,
    availableWidth: number,
    availableHeight: number,
    duration: number,
  ): AnimeAnimParams[] {
    const keyframes: AnimeAnimParams[] = [
      {
        ...this.calcFramePositionAndSize(currentFrame, canvasSize, availableWidth, availableHeight),
        duration: Math.max(0, Math.min(focusDuration, duration)),
        opacity: 1, // fixes odd jump at first render of the new image.
      },
    ];

    if (!duration || duration <= focusDuration) {
      return keyframes;
    }

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

    if (!panFramePosition || !finalFramePosition) {
      return keyframes;
    }

    if (duration <= focusDuration * 2) {
      console.warn("ComicBookCalc.MakeKeyFrames() -> duration is too short for panning, skipping pan animation. duration: " + duration);
      return keyframes;
    }

    keyframes.push(
      {
        ...this.calcFramePositionAndSize(panFramePosition, canvasSize, availableWidth, availableHeight),
        duration: 0,
      },
      {
        ...this.calcFramePositionAndSize(finalFramePosition, canvasSize, availableWidth, availableHeight),
        // duration here is segment duration minus the 2x focusDuration from the first two steps of animation
        duration: Math.max(0, (duration ?? 0) - 2 * focusDuration),
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
