import { AnimeAnimParams } from 'animejs';
import { CanvasSize, ComicFrame, ComicFramePosition } from 'types';

// At which factor should we pane over a frame?
const panningFactor = 1.75;
const focusDuration = 750;
const MAX_ZOOM_VALUE = 3;
const framePadding = 10;

export class ComicBookCalc {
  public static MakeKeyFrames(
    currentFrame: ComicFrame,
    canvasSize: CanvasSize,
    availableWidth: number,
    availableHeight: number,
    duration: number,
  ): AnimeAnimParams[] {
    const framePosition = ComicBookCalc.makeFramePosition(currentFrame);

    const keyframes: AnimeAnimParams[] = [
      {
        ...ComicBookCalc.calcFramePositionAndSize(framePosition, canvasSize, availableWidth, availableHeight),
        duration: focusDuration,
        opacity: 1, // fixes odd jump at first render of the new image.
      },
    ];

    let panFramePosition: ComicFramePosition;
    let finalFramePosition: ComicFramePosition;
    if (ComicBookCalc.shouldDoVerticalPanning(framePosition, availableHeight)) {
      // Vertical pan from top to bottom
      const topHalfFrame = {
        ...currentFrame,
        height: currentFrame.width,
      };

      // Step 1.: Move to the top of the frame.
      panFramePosition = ComicBookCalc.makeFramePosition(topHalfFrame);

      // Step 2.: Pan downwards from the top of the frame to the bottom of the frame.
      // This means the top/left y coordinate end up being is frame's height - width;
      finalFramePosition = ComicBookCalc.makeFramePosition(topHalfFrame);
      finalFramePosition.topLeft.y += currentFrame.height - currentFrame.width + framePadding;

      // this.debug(`${cls} - vertical panning from start: ${JSON.stringify(panFramePosition)} to tl.y: ${finalFramePosition.topLeft.y}`);
    } else if (ComicBookCalc.shouldDoHorizontalPanning(framePosition, availableWidth)) {
      // Horizontal pan from left to right
      const leftHalfFrame = {
        ...currentFrame,
        width: currentFrame.height,
      };

      // Step 1. Move to the left side of the frame.
      panFramePosition = ComicBookCalc.makeFramePosition(leftHalfFrame);

      // Step 2. Pan leftwards from the left of the frame to the right side of the frame.
      // This means top/left x coordinate end up being frame's width - height.
      finalFramePosition = ComicBookCalc.makeFramePosition(leftHalfFrame);
      finalFramePosition.topLeft.x += currentFrame.width - currentFrame.height + framePadding;

      // this.debug(`${cls} - horizontal panning from start: ${JSON.stringify(panFramePosition)} to tl.x: ${finalFramePosition.topLeft.x}`);
    }

    if (panFramePosition && finalFramePosition) {
      keyframes.push(
        {
          ...ComicBookCalc.calcFramePositionAndSize(panFramePosition, canvasSize, availableWidth, availableHeight),
          duration: focusDuration,
        },
        {
          ...ComicBookCalc.calcFramePositionAndSize(finalFramePosition, canvasSize, availableWidth, availableHeight),
          // duration here is segment duration minus the 2x focusDuration from the first two steps of animation
          duration: duration ?? 0 - 2 * focusDuration,
        },
      );
    }

    return keyframes;
  }

  /**
   * Should we do vertical panning?
   *
   * Vertical panning is needed if the ratio between frame's height and width is larger than panningFactor.
   * AND
   * The frame's height is larger than the containers height * panningFactor
   */
  protected static shouldDoVerticalPanning(framePosition: ComicFramePosition, availableHeight: number): boolean {
    return framePosition.height / framePosition.width >= panningFactor && framePosition.height > availableHeight * panningFactor;
  }

  /**
   * Should we do horizontal panning?
   *
   * Horizontal panning is needed if the ratio between frame's width and height is larger than panningFactor.
   * AND
   * The frame's width is larger than the containers width * panningFactor
   */
  protected static shouldDoHorizontalPanning(framePosition: ComicFramePosition, availableWidth: number): boolean {
    return framePosition.width / framePosition.height >= panningFactor && framePosition.width > availableWidth * panningFactor;
  }

  /**
   * Convert a ComicFrame to a ComicFramePosition.
   */
  public static makeFramePosition({ left: x, top: y, width, height }: ComicFrame): ComicFramePosition {
    return {
      width,
      height,
      topLeft: {
        x,
        y,
      },
      bottomRight: {
        x: x + width,
        y: y + height,
      },
    };
  }

  /**
   * Calculate the position and sizing info needed to show a frame within
   * the container element.
   *
   * If the frame too large to fit within the container, the image will be resized.
   */
  public static calcFramePositionAndSize(frame: ComicFramePosition, canvasSize: CanvasSize, availableWidth: number, availableHeight: number): ComicFrame {
    // Start by getting width and height of the container minus the padding.
    const clientWidth = availableWidth - framePadding * 2;
    const clientHeight = availableHeight - framePadding * 2;

    // Get image size info.
    const { width: imageWidth, height: imageHeight } = canvasSize;

    // Destruct the framing info into size and top/left-coordinates.
    const {
      width: frameWidth,
      height: frameHeight,
      topLeft: { x: frameX0, y: frameY0 },
    } = frame;

    /*
     * Scale factor for the frame to fit into the container
     *
     * If the frame is bigger than the container, the comic book page must be scaled down.
     * The image will max be scaled up to value of MAX_ZOOM_VALUE
     */
    const scale = Math.min(MAX_ZOOM_VALUE, clientWidth / frameWidth, clientHeight / frameHeight);

    // eslint-disable-next-line max-len
    // this.debug(`ComicViewerComponent.calcFramePositionAndSize() -> scale: ${scale} -> ${MAX_ZOOM_VALUE} -> ${clientWidth / frameWidth} -> ${clientHeight / frameHeight}`);

    // Resize the image if needed
    const scaledImageWidth = imageWidth * scale;
    const scaledImageHeight = imageHeight * scale;

    // Scaled top/left coordinates are a result of the original coordinate * scale.
    const scaledFrameX0 = -(frameX0 * scale);
    const scaledFrameY0 = -(frameY0 * scale);

    // The frame needs to be centered, if the scaled frame size is smaller than the container size.
    const scaledFrameWidth = frameWidth * scale;

    let xCentering = 0;
    let yCentering = 0;

    if (scaledFrameWidth < clientWidth) {
      xCentering = (clientWidth - scaledFrameWidth) / 2;
    }

    const scaledFrameHeight = frameHeight * scale;
    if (scaledFrameHeight < clientHeight) {
      yCentering = (clientHeight - scaledFrameHeight) / 2;
    }

    return {
      top: yCentering + scaledFrameY0 + framePadding,
      left: xCentering + scaledFrameX0 + framePadding,
      width: scaledImageWidth,
      height: scaledImageHeight,
    };
  }
}
