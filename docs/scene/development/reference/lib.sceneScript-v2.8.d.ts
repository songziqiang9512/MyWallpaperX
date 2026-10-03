/// <reference no-default-lib="true"/>
/** OFFICIAL SCENESCRIPT TYPE DECLARATION - VERSION 2.8 **/

/**
 * ============================================================================
 * SCENESCRIPT ARCHITECTURE HINTS
 * ============================================================================
 * In Wallpaper Engine, SceneScript is a PROPERTY-BOUND scripting system.
 * Scripts are attached to ONE specific property (e.g., 'Scale', 'Color', or 'Text').
 * To bind a script to a property:
 * Find the property in the editor, click on the cogwheel icon next to it, 
 * then select "Bind SceneScript".
 * For general purpose scripts that are not strictly tied to one property of a layer,
 * the 'Visibility' property is typically used (upper right corner on each layer, eye icon).
 * * 1. THE RETURN VALUE RULE (DEFAULT BEHAVIOR): An update event's primary job is to
 * RETURN a value that matches the exact data type of the property it is bound to.
 * - If bound to 'Color', the event receives an existing Vec3 and should return a Vec3.
 * - If bound to 'Text', the event receives an existing String and should return a String.
 * * 2. THE ASSIGNMENT EXCEPTION (COMPLEX LOGIC): Direct assignment (e.g.,
 * `thisLayer.scale = new Vec3(...)`) is allowed and actively encouraged if a script
 * needs to modify MULTIPLE properties at once. For example, if an audio-reactive
 * script calculates data that affects both Color and Scale, assign them directly
 * in one script rather than duplicating heavy audio processing across multiple
 * property scripts to save performance.
 * * 3. PREFER EVENT HOOKS OVER UPDATE: The `update()` event is entirely optional and
 * highly performance-intensive because it executes every single frame. Before placing
 * code in `update()`, always check if your logic is better suited for a specific
 * event hook. For example, if your code only needs to react to initialization, screen
 * resizes, user property changes, or cursor clicks, use the appropriate event
 * (`init()`, `resizeScreen()`, `applyUserProperties()`, `cursorClick()`, etc.) and
 * directly assign the changed properties there. Avoid caching values in global
 * variables during events just to apply them later inside an `update()` loop.
 * * 4. PRAGMATISM OVER ISOLATION: Simplicity and CPU performance trump strict
 * isolation. While a script bound to 'Color' should ideally only handle color,
 * you must break this rule if grouping the logic makes the script significantly
 * cleaner or lighter on the CPU.
 * Additional note: All property scripts should utilize "'use strict';"
 * ============================================================================
 */

/**
 * Component lifecycle hooks for SceneScript properties
 * * These are the lifecycle and interaction events that a SceneScript file can export.
 * To use an event, export a function with the corresponding name.
 * Example: `export function init(value) { ... }`
 */
interface IComponent {
	/**
	 * This initialization function will be called once after the object it belongs to has been created.
	 * * IMPORTANT BINDING NOTE: The type of 'value' depends entirely on the property this script is bound to.
	 * Do not assign new values directly to the property. Instead, you must RETURN the modified value.
	 * @param value The current value of the bound property at initialization.
	 * @returns The modified value to be applied to the property.
	 */
	init?(value: Number | Boolean | String | Vec2 | Vec3 | Vec4 | Mat4 | Mat3): Number | Boolean | String | Vec2 | Vec3 | Vec4;

	/**
	 * This event function will be called every frame for all scripts that export it.
	 * * IMPORTANT PERFORMANCE NOTE: Avoid placing complex tasks or heavy math in this function.
	 * Because it runs every single frame, it can severely impact performance. Use event-driven hooks
	 * like `init`, `resizeScreen`, or `applyUserProperties` instead whenever possible.
	 * * IMPORTANT BINDING NOTE: The type of 'value' depends entirely on the property this script is bound to.
	 * Do not assign new values directly to the property. Instead, you must RETURN the modified value.
	 * @param value The current value of the bound property.
	 * @returns The modified value to be applied to the property.
	 */
	update?(value: Number | Boolean | String | Vec2 | Vec3 | Vec4 | Mat4 | Mat3): Number | Boolean | String | Vec2 | Vec3 | Vec4;

	/**
	 * This event function will be called just before the object it belongs to gets destroyed.
	 */
	destroy?(): void;

	/**
	 * This function will be called every time the wallpaper resizes because of a change to the current resolution.
	 * * IMPORTANT STARTUP NOTE: This is NOT called automatically when the wallpaper is first created.
	 * If you have layout logic that needs to run on creation and on resize, put it in a separate custom
	 * function and call that function from both `init()` and `resizeScreen()`.
	 * @param size The new screen resolution in pixels.
	 */
	resizeScreen?(size: Vec2): void;

	/**
	 * Contains up-to-date values for user properties. This event function will be called once initially
	 * when the wallpaper is loaded and whenever any user properties are being adjusted by the user.
	 * * CRITICAL USAGE NOTE: This object ONLY contains properties that have actually changed.
	 * You MUST check if a property exists using `hasOwnProperty` before accessing it, otherwise the script will fail:
	 * ```javascript
	 * if (changedUserProperties.hasOwnProperty('first_property')) {
	 * // Logic for changedUserProperties.first_property goes here
	 * }
	 * ```
	 * @param changedUserProperties An object containing the current values of exposed user properties that have changed.
	 */
	applyUserProperties?(changedUserProperties: Object): void;

	/**
	 * Contains general app settings. This event function will be called once initially when the wallpaper
	 * is loaded and whenever any general app settings are adjusted by the user.
	 * * CRITICAL USAGE NOTE: This object ONLY contains settings that have actually changed.
	 * You MUST check if a setting exists using `hasOwnProperty` before accessing it, otherwise the script will fail:
	 * ```javascript
	 * if (changedGeneralSettings.hasOwnProperty('language')) {
	 * // Logic for changedGeneralSettings.language goes here
	 * }
	 * ```
	 * @param changedGeneralSettings An object containing global app settings that have changed (currently only language).
	 */
	applyGeneralSettings?(changedGeneralSettings: Object): void;

	/**
	 * This event function will be called when the cursor enters the bounds of the object.
	 */
	cursorEnter?(event: CursorEvent): void;

	/**
	 * This event function will be called when the cursor leaves the bounds of the object.
	 */
	cursorLeave?(event: CursorEvent): void;

	/**
	 * This event function will be called when the cursor has been moved.
	 */
	cursorMove?(event: CursorEvent): void;

	/**
	 * This event function will be called when the cursor is being pressed down on an object.
	 */
	cursorDown?(event: CursorEvent): void;

	/**
	 * This event function will be called when the cursor is being released over an object.
	 */
	cursorUp?(event: CursorEvent): void;

	/**
	 * This event function will be called when the cursor has been pressed and released on the same object.
	 */
	cursorClick?(event: CursorEvent): void;

	/**
	 * This event function will be called when the media integration is turned on or off by the user.
	 */
	mediaStatusChanged?(event: MediaStatusEvent): void;

	/**
	 * This event function will be called when the users starts, stops or pauses media.
	 */
	mediaPlaybackChanged?(event: MediaPlaybackEvent): void;

	/**
	 * This event function will be called when the properties of the currently playing media change.
	 */
	mediaPropertiesChanged?(event: MediaPropertiesEvent): void;

	/**
	 * This event function will be called when the thumbnail of the currently playing media changes.
	 */
	mediaThumbnailChanged?(event: MediaThumbnailEvent): void;

	/**
	 * This event function will be called when the current time of the playing media changes and is only provided by certain applications.
	 */
	mediaTimelineChanged?(event: MediaTimelineEvent): void;
}

/**
 * A vector with 2 dimensions.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/Vec2
 */
class Vec2 {
	x: Number;
	y: Number;

	constructor(x: Number|Vec3|String, y?: Number): Vec2;

	/**
	 * The length.
	 */
	length(): Number;

	/**
	 * The length squared (more efficient for simple comparisons in your code).
	 */
	lengthSqr(): Number;

	/**
	 * Distance to another vector.
	 */
	distance(other: Vec2): Number;

	/**
	 * Distance squared to another vector (more efficient for simple comparisons in your code).
	 */
	distanceSqr(other: Vec2): Number;

	/**
	 * Normalizes the length.
	 */
	normalize(): Vec2;

	/**
	 * Makes a simple copy of the vector.
	 */
	copy(): Vec2;

	/**
	 * Checks if one vector is equal (with epsilon) to another vector.
	 */
	equals(other: Vec2): Boolean;

	/**
	 * Checks if all components are finite numbers.
	 */
	isFinite(): Boolean;

	/**
	 * Returns the vector negated component-wise.
	 */
	negate(): Vec2;

	/**
	 * Adds another vector or number.
	 */
	add(value: Number|Vec2): Vec2;

	/**
	 * Subtracts another vector or number.
	 */
	subtract(value: Number|Vec2): Vec2;

	/**
	 * Multiplies with another vector or number.
	 */
	multiply(value: Number|Vec2): Vec2;

	/**
	 * Divides by another vector or number.
	 */
	divide(value: Number|Vec2): Vec2;

	/**
	 * Computes dot product with value.
	 */
	dot(value: Vec2): Number;

	/**
	 * Reflects along given normal.
	 */
	reflect(normal: Vec2): Vec2;

	/**
	 * Returns perpendicular direction.
	 */
	perpendicular(): Vec2;

	/**
	 * Projects this vector onto another vector.
	 */
	project(value: Vec2): Vec2;

	/**
	 * Returns the angle of the vector in degrees.
	 */
	angle(): Number;

	/**
	 * Returns the signed angle between this vector and another vector in degrees.
	 */
	angleBetween(value: Vec2): Number;

	/**
	 * Rotates the vector by the given angle in degrees.
	 */
	rotate(angle: Number): Vec2;

	/**
	 * Interpolate between this vector and another vector of the same dimension.
	 * @param other The other vector for the interpolation.
	 * @param amount Interpolation value between 0.00 and 1.00 where 1.00 represents the other vector.
	 */
	mix(other: Vec2, amount: Number|Vec2): Vec2;

	/**
	 * Return the smaller value per component of two vectors.
	 */
	min(value: Vec2): Vec2;

	/**
	 * Return the larger value per component of two vectors.
	 */
	max(value: Vec2): Vec2;

	/**
	 * Clamps each component between min and max bounds (each may be a scalar or a vector).
	 */
	clamp(min: Number|Vec2, max: Number|Vec2): Vec2;

	/**
	 * Returns absolute values for each vector component.
	 */
	abs(): Vec2;

	/**
	 * Returns sign of each vector component.
	 */
	sign(): Vec2;

	/**
	 * Rounds each vector component.
	 */
	round(): Vec2;

	/**
	 * Returns floor value of each vector component.
	 */
	floor(): Vec2;

	/**
	 * Returns ceil value of each vector component.
	 */
	ceil(): Vec2;

	/**
	 * Returns the fractional part of each component (x - floor(x)).
	 */
	fract(): Vec2;

	/**
	 * Modulo per component following GLSL semantics: x - y * floor(x / y).
	 */
	mod(value: Number|Vec2): Vec2;

	/**
	 * Per-component step: returns 0 where this < edge, 1 otherwise.
	 */
	step(edge: Number|Vec2): Vec2;

	/**
	 * Per-component Hermite smooth interpolation between min and max edges.
	 */
	smoothStep(min: Number|Vec2, max: Number|Vec2): Vec2;

	/**
	 * Converts components to a string representation that Wallpaper Engine understands.
	 */
	toString(): String;
}

/**
 * A vector with 3 dimensions.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/Vec3
 */
class Vec3 {
	x: Number;
	y: Number;
	z: Number;

	constructor(x: Number|Vec2|String, y?: Number, z?: Number): Vec3;

	/**
	 * Creates a Vec3 from spherical coordinates. Theta is the polar angle from +Y, phi is the azimuth around Y, both in degrees.
	 */
	static fromSpherical(r: Number, theta: Number, phi: Number): Vec3;

	/**
	 * The length.
	 */
	length(): Number;

	/**
	 * The length squared (more efficient for simple comparisons in your code).
	 */
	lengthSqr(): Number;

	/**
	 * Distance to another vector.
	 */
	distance(other: Vec3): Number;

	/**
	 * Distance squared to another vector (more efficient for simple comparisons in your code).
	 */
	distanceSqr(other: Vec3): Number;

	/**
	 * Normalizes the length.
	 */
	normalize(): Vec3;

	/**
	 * Makes a simple copy of the vector.
	 */
	copy(): Vec3;

	/**
	 * Checks if one vector is equal (with epsilon) to another vector.
	 */
	equals(other: Vec3): Boolean;

	/**
	 * Checks if all components are finite numbers.
	 */
	isFinite(): Boolean;

	/**
	 * Returns the vector negated component-wise.
	 */
	negate(): Vec3;

	/**
	 * Adds another vector or number.
	 */
	add(value: Number|Vec2|Vec3): Vec3;

	/**
	 * Subtracts another vector or number.
	 */
	subtract(value: Number|Vec2|Vec3): Vec3;

	/**
	 * Multiplies with another vector or number.
	 */
	multiply(value: Number|Vec2|Vec3): Vec3;

	/**
	 * Divides by another vector or number.
	 */
	divide(value: Number|Vec2|Vec3): Vec3;

	/**
	 * Computes cross product with value.
	 */
	cross(value: Vec3): Vec3;

	/**
	 * Computes dot product with value.
	 */
	dot(value: Vec3): Number;

	/**
	 * Reflects along given normal.
	 */
	reflect(normal: Vec3): Vec3;

	/**
	 * Refracts along given normal using the ratio of indices of refraction (eta).
	 * Follows GLSL refract semantics; returns the zero vector for total internal reflection.
	 */
	refract(normal: Vec3, eta: Number): Vec3;

	/**
	 * Projects this vector onto another vector.
	 */
	project(value: Vec3): Vec3;

	/**
	 * Returns the unsigned angle between this vector and another vector in degrees.
	 */
	angleBetween(value: Vec3): Number;

	/**
	 * Converts this vector to spherical coordinates. Returns a Vec3 of (r, theta, phi), with theta and phi in degrees.
	 */
	toSpherical(): Vec3;

	/**
	 * Interpolate between this vector and another vector of the same dimension.
	 * @param other The other vector for the interpolation.
	 * @param amount Interpolation value between 0.00 and 1.00 where 1.00 represents the other vector.
	 */
	mix(other: Vec3, amount: Number|Vec3): Vec3;

	/**
	 * Return the smaller value per component of two vectors.
	 */
	min(value: Vec3): Vec3;

	/**
	 * Return the larger value per component of two vectors.
	 */
	max(value: Vec3): Vec3;

	/**
	 * Clamps each component between min and max bounds (each may be a scalar or a vector).
	 */
	clamp(min: Number|Vec3, max: Number|Vec3): Vec3;

	/**
	 * Returns absolute values for each vector component.
	 */
	abs(): Vec3;

	/**
	 * Returns sign of each vector component.
	 */
	sign(): Vec3;

	/**
	 * Rounds each vector component.
	 */
	round(): Vec3;

	/**
	 * Returns floor value of each vector component.
	 */
	floor(): Vec3;

	/**
	 * Returns ceil value of each vector component.
	 */
	ceil(): Vec3;

	/**
	 * Returns the fractional part of each component (x - floor(x)).
	 */
	fract(): Vec3;

	/**
	 * Modulo per component following GLSL semantics: x - y * floor(x / y).
	 */
	mod(value: Number|Vec3): Vec3;

	/**
	 * Per-component step: returns 0 where this < edge, 1 otherwise.
	 */
	step(edge: Number|Vec3): Vec3;

	/**
	 * Per-component Hermite smooth interpolation between min and max edges.
	 */
	smoothStep(min: Number|Vec3, max: Number|Vec3): Vec3;

	/**
	 * Converts components to a string representation that Wallpaper Engine understands.
	 */
	toString(): String;
}

/**
 * A 4x4 matrix.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/Mat4
 */
class Mat4 {
	m: Array;

	/**
	 * Creates an identity matrix.
	 */
	constructor(): Mat4;

	/**
	 * Creates an identity matrix.
	 */
	static identity(): Mat4;

	/**
	 * Creates a translation matrix from a Vec2 or Vec3.
	 */
	static fromTranslation(v: Vec2|Vec3): Mat4;

	/**
	 * Creates a uniform or per-axis scale matrix.
	 */
	static fromScale(v: Number|Vec3): Mat4;

	/**
	 * Creates a rotation matrix around an arbitrary axis. Angle is in degrees.
	 */
	static fromRotation(angle: Number, axis: Vec3): Mat4;

	/**
	 * Creates a rotation matrix from Euler angles in degrees.
	 */
	static fromEuler(x: Number|Vec3, y?: Number, z?: Number): Mat4;

	/**
	 * Creates a matrix from three orthonormal basis vectors (column-wise).
	 */
	static fromBasis(right: Vec3, up: Vec3, forward: Vec3): Mat4;

	/**
	 * Creates a view matrix from an eye position, a target center and an up vector.
	 */
	static lookAt(eye: Vec3, center: Vec3, up: Vec3): Mat4;

	/**
	 * Composes a transform as T * R * S, with rotation as Euler angles in degrees.
	 */
	static compose(translation: Vec3, rotation: Vec3, scale: Vec3): Mat4;

	/**
	 * Gets or sets the translation of the matrix.
	 */
	translation(position?: Vec2|Vec3): Vec3;

	/**
	 * Gets right vector. (Red axis)
	 */
	right(): Vec3;

	/**
	 * Gets up vector. (Green axis)
	 */
	up(): Vec3;

	/**
	 * Gets forward vector. (Blue axis)
	 */
	forward(): Vec3;

	/**
	 * Element-wise matrix addition.
	 */
	add(other: Mat4): Mat4;

	/**
	 * Element-wise matrix subtraction.
	 */
	subtract(other: Mat4): Mat4;

	/**
	 * Multiplies with another matrix, a Vec4, or a scalar.
	 */
	multiply(value: Mat4|Vec4|Number): Mat4|Vec4;

	/**
	 * Right-multiplies by a translation. Equivalent to this * fromTranslation(v).
	 */
	translate(v: Vec2|Vec3): Mat4;

	/**
	 * Right-multiplies by a rotation around an arbitrary axis. Angle is in degrees.
	 */
	rotate(angle: Number, axis: Vec3): Mat4;

	/**
	 * Right-multiplies by a scale (uniform or per-axis).
	 */
	scale(v: Number|Vec3): Mat4;

	/**
	 * Transforms a point (treated as having w = 1).
	 */
	transformPoint(v: Vec3): Vec3;

	/**
	 * Transforms a direction vector (treated as having w = 0, ignoring translation).
	 */
	transformDirection(v: Vec3): Vec3;

	/**
	 * Returns the transposed matrix.
	 */
	transpose(): Mat4;

	/**
	 * Returns the inverse matrix.
	 */
	inverse(): Mat4;

	/**
	 * Returns the determinant.
	 */
	determinant(): Number;

	/**
	 * Extracts Euler angles in degrees as a Vec3.
	 */
	extractEuler(): Vec3;

	/**
	 * Returns the 3x3 normal matrix (transpose of the inverse of the upper-left 3x3).
	 */
	normalMatrix(): Mat3;

	/**
	 * Decomposes the matrix into translation, Euler rotation (degrees) and scale.
	 * Returns an object of shape { translation: Vec3, rotation: Vec3, scale: Vec3 }.
	 */
	decompose(): Object;

	/**
	 * Makes a simple copy of the matrix.
	 */
	copy(): Mat4;

	/**
	 * Checks if one matrix is equal (with epsilon) to another matrix.
	 */
	equals(other: Mat4): Boolean;

	/**
	 * Converts components to a string representation that Wallpaper Engine understands.
	 */
	toString(): String;
}

/**
 * A 3x3 matrix.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/Mat3
 */
class Mat3 {
	m: Array;

	/**
	 * Creates an identity matrix.
	 */
	constructor(): Mat3;

	/**
	 * Creates an identity matrix.
	 */
	static identity(): Mat3;

	/**
	 * Creates a 2D translation matrix.
	 */
	static fromTranslation(v: Vec2): Mat3;

	/**
	 * Creates a uniform or per-axis 2D scale matrix.
	 */
	static fromScale(v: Number|Vec2): Mat3;

	/**
	 * Creates a 2D rotation matrix. Angle is in degrees.
	 */
	static fromRotation(angle: Number): Mat3;

	/**
	 * Creates a matrix from two 2D basis vectors (column-wise).
	 */
	static fromBasis(right: Vec2, up: Vec2): Mat3;

	/**
	 * Creates a Mat3 from the upper-left 3x3 of a Mat4.
	 */
	static fromMat4(m: Mat4): Mat3;

	/**
	 * Composes a 2D transform as T * R * S, with rotation as a degree angle.
	 */
	static compose(translation: Vec2, rotation: Number, scale: Vec2): Mat3;

	/**
	 * Gets or sets the translation of the matrix.
	 */
	translation(position?: Vec2): Vec2;

	/**
	 * Get forward angle of matrix in degrees.
	 */
	angle(): Number;

	/**
	 * Element-wise matrix addition.
	 */
	add(other: Mat3): Mat3;

	/**
	 * Element-wise matrix subtraction.
	 */
	subtract(other: Mat3): Mat3;

	/**
	 * Multiplies with another matrix, a Vec3, or a scalar.
	 */
	multiply(value: Mat3|Vec3|Number): Mat3|Vec3;

	/**
	 * Right-multiplies by a translation. Equivalent to this * fromTranslation(v).
	 */
	translate(v: Vec2): Mat3;

	/**
	 * Right-multiplies by a rotation. Angle is in degrees.
	 */
	rotate(angle: Number): Mat3;

	/**
	 * Right-multiplies by a scale (uniform or per-axis).
	 */
	scale(v: Number|Vec2): Mat3;

	/**
	 * Transforms a 2D point (applies translation).
	 */
	transformPoint(v: Vec2): Vec2;

	/**
	 * Transforms a 2D direction (ignores translation).
	 */
	transformDirection(v: Vec2): Vec2;

	/**
	 * Returns the transposed matrix.
	 */
	transpose(): Mat3;

	/**
	 * Returns the determinant.
	 */
	determinant(): Number;

	/**
	 * Returns the inverse matrix.
	 */
	inverse(): Mat3;

	/**
	 * Decomposes the matrix into translation, rotation (degrees) and scale.
	 * Returns an object of shape { translation: Vec2, rotation: Number, scale: Vec2 }.
	 */
	decompose(): Object;

	/**
	 * Makes a simple copy of the matrix.
	 */
	copy(): Mat3;

	/**
	 * Checks if one matrix is equal (with epsilon) to another matrix.
	 */
	equals(other: Mat3): Boolean;

	/**
	 * Converts components to a string representation that Wallpaper Engine understands.
	 */
	toString(): String;
}

/**
 * A vector with 4 dimensions.
 */
class Vec4 {
	x: Number;
	y: Number;
	z: Number;
	w: Number;

	constructor(x: Number|Vec2|Vec3|Vec4|String, y?: Number, z?: Number, w?: Number): Vec4;

	/**
	 * The length.
	 */
	length(): Number;

	/**
	 * The length squared (more efficient for simple comparisons in your code).
	 */
	lengthSqr(): Number;

	/**
	 * Distance to another vector.
	 */
	distance(other: Vec4): Number;

	/**
	 * Distance squared to another vector (more efficient for simple comparisons in your code).
	 */
	distanceSqr(other: Vec4): Number;

	/**
	 * Normalizes the length.
	 */
	normalize(): Vec4;

	/**
	 * Makes a simple copy of the vector.
	 */
	copy(): Vec4;

	/**
	 * Checks if one vector is equal (with epsilon) to another vector.
	 */
	equals(other: Vec4): Boolean;

	/**
	 * Checks if all components are finite numbers.
	 */
	isFinite(): Boolean;

	/**
	 * Returns the vector negated component-wise.
	 */
	negate(): Vec4;

	/**
	 * Adds another vector or number.
	 */
	add(value: Number|Vec4): Vec4;

	/**
	 * Subtracts another vector or number.
	 */
	subtract(value: Number|Vec4): Vec4;

	/**
	 * Multiplies with another vector or number.
	 */
	multiply(value: Number|Vec4): Vec4;

	/**
	 * Divides by another vector or number.
	 */
	divide(value: Number|Vec4): Vec4;

	/**
	 * Computes dot product with value.
	 */
	dot(value: Vec4): Number;

	/**
	 * Reflects along given normal.
	 */
	reflect(normal: Vec4): Vec4;

	/**
	 * Projects this vector onto another vector.
	 */
	project(value: Vec4): Vec4;

	/**
	 * Interpolate between this vector and another vector of the same dimension.
	 * @param other The other vector for the interpolation.
	 * @param amount Interpolation value between 0.00 and 1.00 where 1.00 represents the other vector.
	 */
	mix(other: Vec4, amount: Number|Vec4): Vec4;

	/**
	 * Return the smaller value per component of two vectors.
	 */
	min(value: Vec4): Vec4;

	/**
	 * Return the larger value per component of two vectors.
	 */
	max(value: Vec4): Vec4;

	/**
	 * Clamps each component between min and max bounds (each may be a scalar or a vector).
	 */
	clamp(min: Number|Vec4, max: Number|Vec4): Vec4;

	/**
	 * Returns absolute values for each vector component.
	 */
	abs(): Vec4;

	/**
	 * Returns sign of each vector component.
	 */
	sign(): Vec4;

	/**
	 * Rounds each vector component.
	 */
	round(): Vec4;

	/**
	 * Returns floor value of each vector component.
	 */
	floor(): Vec4;

	/**
	 * Returns ceil value of each vector component.
	 */
	ceil(): Vec4;

	/**
	 * Returns the fractional part of each component (x - floor(x)).
	 */
	fract(): Vec4;

	/**
	 * Modulo per component following GLSL semantics: x - y * floor(x / y).
	 */
	mod(value: Number|Vec4): Vec4;

	/**
	 * Per-component step: returns 0 where this < edge, 1 otherwise.
	 */
	step(edge: Number|Vec4): Vec4;

	/**
	 * Per-component Hermite smooth interpolation between min and max edges.
	 */
	smoothStep(min: Number|Vec4, max: Number|Vec4): Vec4;

	/**
	 * Converts components to a string representation that Wallpaper Engine understands.
	 */
	toString(): String;
}

/**
 * A vector with 4 dimensions.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/CameraTransforms
 */
class CameraTransforms {
	eye: Vec3;
	center: Vec3;
	up: Vec3;
	zoom: Number;
}

/**
 * An animation event fired by puppet or property animations
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/AnimationEvent
 */
class AnimationEvent {
	name: String;
	frame: Number;
}

/**
 * Event used for all cursor related callbacks.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/CursorEvent
 */
class CursorEvent {
	/**
	 * 2D position on screen in pixels. NOT USED.
	 */
	//screenPosition: Vec2;

	/**
	 * 3D Position of the cursor in world space. Only X and Y are supported right now.
	 */
	worldPosition: Vec3

	/**
	 * 3D position local to the object. Only X and Y are supported right now.
	 */
	localPosition: Vec3;

	/**
	 * Currently always 0 for left mouse button. NOT USED.
	 */
	// button: Number;

	/**
	 * Hit box name when clicking on a puppet warp model. The custom name of the bone or if none was defined, the index of the bone.
	 */
	hitBox?: String;
}

/**
 * Event containing all media information. Many applications only fill out the title and artist member.
 */
class MediaPropertiesEvent {
	/**
	 * Track title.
	 */
	title: String;

	/**
	 * Artist.
	 */
	artist: String;

	/**
	 * Track sub title.
	 */
	subTitle: String;

	/**
	 * Album title.
	 */
	albumTitle: String;

	/**
	 * Album artist.
	 */
	albumArtist: String;

	/**
	 * List of genres, separated by comma.
	 */
	genres: String;

	/**
	 * Content type, i.e. audio or video.
	 */
	contentType: String;
}

/**
 * Event triggered when the thumbnail image has been updated.
 */
class MediaThumbnailEvent {
	/**
	 * Set when a thumbnail is currently available.
	 */
	hasThumbnail: Boolean;

	/**
	 * Primary color in normalized rgb.
	 */
	primaryColor: Vec3;

	/**
	 * Secondary color in normalized rgb.
	 */
	secondaryColor: Vec3;

	/**
	 * Tertiary color in normalized rgb.
	 */
	tertiaryColor: Vec3;

	/**
	 * Text color guaranteed to have sufficient contrast with primary color. May be secondary or tertiary color when possible.
	 */
	textColor: Vec3;

	/**
	 * Black or white, depending on what has higher contrast with the primary color.
	 */
	highContrastColor: Vec3;
}

/**
 * Event sent when media is being started, paused or stopped.
 */
class MediaPlaybackEvent {
	/**
	 * Current playback state.
	 */
	state: Number;

	/**
	 * Audio is stopped.
	 */
	static readonly PLAYBACK_STOPPED: Number = 0;

	/**
	 * Audio is playing.
	 */
	static readonly PLAYBACK_PLAYING: Number = 1;

	/**
	 * Audio is paused.
	 */
	static readonly PLAYBACK_PAUSED: Number = 2;
}

/**
 * Event containing media position and duration. Sent frequently while media is playing.
 */
class MediaTimelineEvent {
	/**
	 * Time passed in seconds.
	 */
	position: Number;

	/**
	 * Total media duration in seconds.
	 */
	duration: Number;
}

/**
 * Event sent when media integration is being enabled or disabled.
 */
class MediaStatusEvent {
	/**
	 * Whether media integration support is enabled/available.
	 */
	enabled: Boolean;
}

/**
 * Math utilities.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/module/WEMath
 */
declare module 'WEMath' {
	/**
	 * Remaps value between min and max into [0, 1] range.
	 */
	export function smoothStep(min: Number, max: Number, value: Number): Number;
	/**
	 * Interpolates from a to b based on value.
	 */
	export function mix(a: Number, b: Number, value: Number): Number;
	/**
	 * Factor to conver degrees to radians.
	 */
	export let deg2rad: Number;
	/**
	 * Factor to conver radians to degrees.
	 */
	export let rad2deg: Number;
}

/**
 * Linear algebra utilities.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/module/WEVector
 */
declare module 'WEVector' {
	/**
	 * Create a 2D directional vector from an angle (degrees).
	 */
	export function angleVector2(angle: Number): Vec2;
	/**
	 * Create an angle (degrees) matching a 2D directional vector.
	 */
	export function vectorAngle2(direction: Vec2): Number;
}

/**
 * Color utilities.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/module/WEColor
 */
declare module 'WEColor' {
	/**
	 * Converts a normalized RGB vector to a normalized HSV vector.
	 */
	export function rgb2hsv(rgb: Vec3): Vec3;

	/**
	 * Converts a normalized HSV vector to a normalized RGB vector.
	 */
	export function hsv2rgb(hsv: Vec3): Vec3;

	/**
	 * Normalizes a color vector from 0..255 to 0..1.
	 */
	export function normalizeColor(rgb: Vec3): Vec3;

	/**
	 * Expends a color vector from 0..1 to 0..255.
	 */
	export function expandColor(rgb: Vec3): Vec3;
}

/**
 * Audio buffers for audio response. All buffers have the same length.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/AudioBuffers
 */
class AudioBuffers {
	left: Float32Array;
	right: Float32Array;
	average: Float32Array;
}

/**
 * Generic object class that every scene object inherits from.
 */
interface IObject {
	/**
	 * Get an animation object by name. Leave empty to get the animation object bound to the current property.
	 */
	getAnimation(name?: String): IAnimation;
}

/**
 * The object this property is bound to.
 */
interface IThisPropertyObjectBase extends IObject {

}

/**
 * Material that includes shader property access and textures.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IMaterial
 */
interface IMaterial extends IObject {

}

/**
 * Effect layer on an image.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IEffect
 */
interface IEffect extends IObject {
	/**
	 * Gets materials associated with this effect.
	 */
	getMaterial(index: Number): IMaterial;

	/**
	 * Get number of materials used by this effect.
	 */
	getMaterialCount(): Number;

	/**
	 * Set a property value on all materials used by this effect that have a matching property.
	 */
	setMaterialProperty(propertyName: String, value: Number|Vec2|Vec3|Vec4): void;

	/**
	 * Execute a custom render function defined by the effect.
	 */
	executeMaterialFunction(propertyName: String): void;

	/**
	 * Whether is currently visible.
	 */
	visible: Boolean;

	/**
	 * Custom name entered in editor.
	 */
	name: String;
}

/**
 * A generic property animation.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/ITextureAnimation
 */
interface ITextureAnimation {
	/**
	 * Returns the number of frames of the entire animation.
	 */
	readonly frameCount: Number;

	/**
	 * The duration of the animation.
	 */
	readonly duration: Number;

	/**
	 * Speed factor of the texture animation.
	 */
	rate: Number;

	/**
	 * Whether or not this animation should loop.
	 */
	//loop: Boolean;

	/**
	 * Start playing the animation if it's paused or stopped.
	 */
	play(): void;

	/**
	 * Pause the animation.
	 */
	pause(): void;

	/**
	 * Stop the animation and reset the current time to zero.
	 */
	stop(): void;

	/**
	 * Checks if the animation is currently playing.
	 */
	isPlaying(): Boolean;

	/**
	 * Returns the current frame of the animation.
	 */
	getFrame(): Number;

	/**
	 * Changes the frame that is currently displayed, works with paused and running animations.
	 */
	setFrame(frame: Number): void;

	/**
	 * Re-joins the animation with the shared animation timer of all materials using this texture.
	 */
	join(): void;
}

/**
 * A generic property animation.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IVideoTexture
 */
interface IVideoTexture {
	/**
	 * The duration of the animation.
	 */
	readonly duration: Number;

	/**
	 * Speed factor of the texture animation.
	 */
	rate: Number;

	/**
	 * Whether or not this animation should loop.
	 */
	loop: Boolean;

	/**
	 * Start playing the animation if it's paused or stopped.
	 */
	play(): void;

	/**
	 * Pause the animation.
	 */
	pause(): void;

	/**
	 * Stop the animation and reset the current time to zero.
	 */
	stop(): void;

	/**
	 * Checks if the animation is currently playing.
	 */
	isPlaying(): Boolean;

	/**
	 * Returns the current time of the video.
	 */
	getCurrentTime(): Number;

	/**
	 * Changes the current time of the video.
	 */
	setCurrentTime(time: Number): void;

	/**
	 * Add a callback to be fired every time the video reaches the end.
	 */
	addEndedCallback(callback: Function): void;
}

/**
 * The Animation layer object for puppet animations. New animation layers can be created with the following config properties:
 * config.blendin: Boolean - Automatically blend the start of the animation smoothly.
 * config.blendout: Boolean - Automatically blend the end of the animation smoothly.
 * config.blendtime: Number - Time in seconds how long blending in and out will take.
 * config.autosort: Boolean - Insert layer after all opaque layers, but before any additive layers.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IAnimationLayer
 */
interface IAnimationLayer extends IObject {
	/**
	 * The framerate of the animation.
	 */
	readonly fps: Number;

	/**
	 * Returns the number of frames of the entire animation.
	 */
	readonly frameCount: Number;

	/**
	 * The duration of the animation.
	 */
	readonly duration: Number;

	/**
	 * The custom name of the animation.
	 */
	name: String;

	/**
	 * The speed of the animation.
	 */
	rate: Number;

	/**
	 * The blend amount of the animation.
	 */
	blend: Number;

	/**
	 * Whether the animation layer is currently visible.
	 */
	visible: Boolean;

	/**
	 * Start playing the animation if it's paused or stopped.
	 */
	play(): void;

	/**
	 * Pause the animation.
	 */
	pause(): void;

	/**
	 * Stop the animation and reset the current time to zero.
	 */
	stop(): void;

	/**
	 * Checks if the animation is currently playing.
	 */
	isPlaying(): Boolean;

	/**
	 * Returns the current frame of the animation.
	 */
	getFrame(): Number;

	/**
	 * Changes the frame that is currently displayed.
	 */
	setFrame(frame: Number): void;

	/**
	 * Add a callback to be fired every time the animation layer reaches the end.
	 */
	addEndedCallback(callback: Function): void;
}

/**
 * Properties only available on sound objects
 *  https://docs.wallpaperengine.io/scene/scenescript/reference/class/IAnimationLayer
 */
interface ISoundLayer {
	/**
	 * Check if we're playing any sound.
	 */
	isPlaying(): Boolean;

	/**
	 * Play or resume playing.
	 */
	play(): void;

	/**
	 * Stop all sounds.
	 */
	stop(): void;

	/**
	 * Pause all sounds.
	 */
	pause(): void;

	/**
	 * Adjust volume.
	 */
	volume: Number;
}

/**
 * Base class for image and text layers.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IEffectLayer
 */
interface IEffectLayer {
	/**
	 * Find a material effect by its name or index.
	 */
	getEffect(name: String|Number): IEffect;

	/**
	 * Get number of effects used by this image layer.
	 */
	getEffectCount(): Number

	/**
	 * Get a 2D transformation matrix in texture space of this layer for an attachment on any layer of the scene.
	 * Useful to project or center 2D effects on compose layers to attachments in the world on other layers.
	 */
	transformAttachmentToTexture(attachmentLayer:String|Number|ILayer, attachmentName: String|Number): Mat3;

	/**
	 * Resolution of the image layer in pixels. Only read this, do not write.
	 */
	readonly size: Vec2;

	/**
	 * If set to true, the layer will use perspective rendering instead of flat rendering.
	 */
	perspective: Boolean;

	/**
	 * If set to true, the layer will trigger cursor events.
	 */
	solid: Boolean;
}

/**
 * Properties only available on text layer objects
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/ITextLayer
 */
interface ITextLayer {
	/**
	 * The text that will be displayed.
	 */
	text: String;

	/**
	 * Text color.
	 */
	color: Vec3;

	/**
	 * The opacity.
	 */
	alpha: Number;

	/**
	 * Enables the text background.
	 */
	opaquebackground: Boolean;

	/**
	 * Sets the background color.
	 */
	backgroundcolor: Vec3;

	/**
	 * Size of the font in points for 300 DPI.
	 */
	pointsize: Number;

	/**
	 * Font path.
	 */
	font: String;

	/**
	 * Padding in pixels.
	 */
	padding: Number;

	/**
	 * Horizontal text alignment: left, center, right.
	 */
	horizontalalign: String;

	/**
	 * Vertical text alignment: center, top, bottom.
	 */
	verticalalign: String;

	/**
	 * Dynamic screen anchor: none, center, top, topright, right
	 * bottomright, bottom, bottomleft, left, topleft.
	 */
	anchor: String;

	/**
	 * Enable row limit.
	 */
	limitrows: Boolean;

	/**
	 * Max number of rows.
	 */
	maxrows: Number;

	/**
	 * Enable width limit.
	 */
	limitwidth: Boolean;

	/**
	 * Max width in pixels.
	 */
	maxwidth: Number;
}

/**
 * Instance properties that allow particles to be different per layer.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IParticleSystemInstance
 */
interface IParticleSystemInstance {
	/**
	 * Opacity of the particle system.
	 */
	alpha: Number;

	/**
	 * Size multipler of the particle system.
	 */
	size: Number;

	/**
	 * Multiplier of particle being emitted.
	 */
	count: Number;

	/**
	 * Velocity multipler of all particles.
	 */
	speed: Number;

	/**
	 * Multipler for lifetime of particles.
	 */
	lifetime: Number;

	/**
	 * Playback rate simulation and emission.
	 */
	rate: Number;

	/**
	 * Normalized color value to adjust particles by.
	 */
	colorn: Number;

	/**
	 * Position of control point 0.
	 */
	controlpoint0: Vec3;

	/**
	 * Position of control point 1.
	 */
	controlpoint1: Vec3;

	/**
	 * Position of control point 2.
	 */
	controlpoint2: Vec3;

	/**
	 * Position of control point 3.
	 */
	controlpoint3: Vec3;

	/**
	 * Position of control point 4.
	 */
	controlpoint4: Vec3;

	/**
	 * Position of control point 5.
	 */
	controlpoint5: Vec3;

	/**
	 * Position of control point 6.
	 */
	controlpoint6: Vec3;

	/**
	 * Position of control point 7.
	 */
	controlpoint7: Vec3;
}

/**
 * Properties only available for particle systems.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IParticleSystem
 */
interface IParticleSystem {
	/**
	 * If the particle has stopped, this will restart the emission and start simulating again.
	 */
	play(): void;

	/**
	 * This will stop emitting new particles but the existing ones will continue to simulate and render.
	 */
	pause(): void;

	/**
	 * This will remove all particles immediately and stop emitting new ones.
	 */
	stop(): void;

	/**
	 * Check if the particle is emitting anything right now or any particles are being simulated.
	 */
	isPlaying(): Boolean;

	/**
	 * Emit x number of particles instantly, disregarding whether the system is stopped or paused.
	 */
	emitParticles(count?: Number): void;

	/**
	 * Access to instance properties.
	 */
	instance: IParticleSystemInstance;
}

/**
 * Properties only available on image layer objects and solids.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IImageLayer
 */
interface IImageLayer {
	/**
	 * Opacity of the layer.
	 */
	alpha: Number;

	/**
	 * Image color.
	 */
	color: Vec3;

	/**
	 * Image alignment (center, top, right, bottom, left, topright etc).
	 */
	alignment: String;

	/**
	 * Gets the texture animation if the albedo texture of this image layer is a sprite sheet/GIF.
	 */
	getTextureAnimation(): ITextureAnimation;

	/**
	 * Gets the video texture if the albedo texture of this image layer is a video file.
	 */
	getVideoTexture(): IVideoTexture;

	/**
	 * Get the number of animation layers currently used on this layer.
	 */
	getAnimationLayerCount(): Number;

	/**
	 * Get an existing animation layer object by name or index.
	 */
	getAnimationLayer(name: String|Number): IAnimationLayer;

	/**
	 * Create a new animation layer by animation name or JSON config. Only play the animation once, then remove it automatically. See IAnimationLayer for config options.
	 */
	createAnimationLayer(animation: String|Object, config?: Object): IAnimationLayer;

	/**
	 * Create a new animation layer by animation name or JSON config. Only play the animation once, then remove it automatically. See IAnimationLayer for config options.
	 */
	playSingleAnimation(animation: String|Object, config?: Object): IAnimationLayer;

	/**
	 * Remove an existing animation layer by name, index or IAnimationLayer object reference.
	 */
	destroyAnimationLayer(animationLayer: String|Object|IAnimationLayer): Boolean;

	/**
	 * Get the number of skeletal bones.
	 */
	getBoneCount(): Number;

	/**
	 * Get world bone transform by name or index.
	 */
	getBoneTransform(bone: String|Number): Mat4;

	/**
	 * Set world bone transform by name or index.
	 */
	setBoneTransform(bone: String|Number, transform: Mat4): void;

	/**
	 * Get local bone transform by name or index.
	 */
	getLocalBoneTransform(bone: String|Number): Mat4;

	/**
	 * Set local bone transform by name or index.
	 */
	setLocalBoneTransform(bone: String|Number, transform: Mat4): void;

	/**
	 * Get local bone angles by name or index.
	 */
	getLocalBoneAngles(bone: String|Number): Vec3;

	/**
	 * Set local bone angles by name or index.
	 */
	setLocalBoneAngles(bone: String|Number, angles: Vec3): void;

	/**
	 * Get local bone origin by name or index.
	 */
	getLocalBoneOrigin(bone: String|Number): Vec3;

	/**
	 * Set local bone origin by name or index.
	 */
	setLocalBoneOrigin(bone: String|Number, origin: Vec3): void;

	/**
	 * Get the index of a bone by name.
	 */
	getBoneIndex(name: String): Number;

	/**
	 * Get the index of a bone by name.
	 */
	getBoneParentIndex(child: Number|String): Number;

	/**
	 * Apply directional or angular impulse to a physics bone.
	 */
	applyBonePhysicsImpulse(bone?: String|Number, directionalImpulse: Vec3, angularImpulse: Vec3): void;

	/**
	 * Resets physics forces and position.
	 */
	resetBonePhysicsSimulation(bone?: String|Number): void;

	/**
	 * Get the index of a blend shape by name.
	 */
	getBlendShapeIndex(name: String): Number;

	/**
	 * Get blend shape weight by name or index.
	 */
	getBlendShapeWeight(blendShape: String|Number): Number;

	/**
	 * Set blend shape weight by name or index.
	 */
	setBlendShapeWeight(blendShape: String|Number, weight: Number): void;
}

/**
 * Properties only available on model layers.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IModelLayer
 */
interface IModelLayer {
	/**
	 * If set to true, the layer will use perspective rendering instead of flat rendering.
	 */
	perspective: Boolean;

	/**
	 * Enables root motion from any active animation layers.
	 */
	rootmotion: Boolean;

	/**
	 * Get the number of animation layers currently used on this layer.
	 */
	getAnimationLayerCount(): Number;

	/**
	 * Get an existing animation layer object by name or index.
	 */
	getAnimationLayer(name: String|Number): IAnimationLayer;

	/**
	 * Create a new animation layer by animation name or JSON config.
	 */
	createAnimationLayer(animation: String|Object): IAnimationLayer;

	/**
	 * Create a new animation layer by animation name or JSON config. Only play the animation once, then remove it automatically. See IAnimationLayer for config options.
	 */
	playSingleAnimation(animation: String|Object, config?: Object): IAnimationLayer;

	/**
	 * Remove an existing animation layer by name, index or IAnimationLayer object reference.
	 */
	destroyAnimationLayer(animationLayer: String|Object|IAnimationLayer): Boolean;
}

/**
 * Properties only available on model layers.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/ICamera
 */
interface ICamera {
	/**
	 * The field of view (For 3D scenes only).
	 */
	fov: Number;

	/**
	 * The zoom multiplier (For 2D scenes only).
	 */
	zoom: Number;
}

/**
 * Model data that can be used to create a model layer with custom geometry
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IModelData
 */
interface IModelData extends IObject {
	/**
	 * Applies new model data to one or multiple shapes. This is a high performance method that you may call every frame in update.
	 * You need to ensure that your data can be accepted: same buffer lengths, same formats/types. See IScene.createModelData
	 * for details of the shape configuration object. You should only pass the options that you intend to update.
	 * You can also skip the `shapes` array here and just pass a single shape config object if you only care about the first shape.
	 */
	applyData(shapes: Object|Array): void;

	/**
	 * Replaces the model data with different, potentially incompatible data.
	 * * CRITICAL RULE: NEVER call this method inside the `update()` event. Doing so would cause severe performance degradation and will throw an exception.
	 * * It should ONLY be used in event-driven callbacks (such as `applyUserProperties()`) when a state change requires the model geometry to be entirely swapped out.
	 * The buffer lengths or format may be changed or shapes added/removed.
	 * See IScene.createModelData for details of the shape configuration object. You should only pass the options that you intend to change.
	 * You can also skip the `shapes` array here and just pass a single shape config object if you only care about the first shape. If you pass
	 * `null` for a shape in the array or for the index buffer, you can delete the existing shape/buffer in the engine.
	 */
	replaceData(shapes: Object|Array): void;

	/**
	 * Vertex format position flag, 3 floats. Position (px, py, pz).
	 */
	readonly POSITION: String = 'position';

	/**
	 * Vertex format normal flag, 3 floats. Normalized vector (nx, ny, nz).
	 */
	readonly NORMAL: String = 'normal';

	/**
	* Vertex format signed tangent flag, 4 floats required. Normalized tangent vector (tx, ty, tz) in first 3 floats. Sign of cross(normal, tangent) in last float (tw) to orient the bitangent.
	* Critical note: The texture space has the Y axis inverted so this must be represented in the bitangent sign.
	*/
	readonly TANGENT_SIGNED: String = 'tangentSigned';

	/**
	 * Vertex format uv flag, 2 floats. Texture coordinates (u, v).
	 */
	readonly UV: String = 'uv';

	/**
	 * Vertex format color flag, 4 floats. Normalized color with opacity (r, g, b, a).
	 */
	readonly COLOR: String = 'color';
}

/**
 * Includes common properties for each layer and specific functions that will only work on a particular type of layer.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/ILayer
 */
interface ILayer extends IObject, IImageLayer, ISoundLayer, IEffectLayer, ITextLayer, IParticleSystem, IModel, ICamera {
	/**
	 * Position of the layer.
	 */
	origin: Vec3;

	/**
	 * Orientation of the layer in euler angles and degrees.
	 */
	angles: Vec3;

	/**
	 * Scale of the layer.
	 */
	scale: Vec3;

	/**
	 * Controls parallax strength along x and y axes individually.
	 */
	parallaxDepth: Vec2;

	/**
	 * Custom name for this layer.
	 */
	name: String;

	/**
	 * Visibility currently only for image layers and particles.
	 */
	visible: Boolean;

	/**
	 * Gets the current world transform matrix.
	 */
	getTransformMatrix(): Mat4;

	/**
	 * Rotates the object around the axes defined by its current transformation.
	 */
	rotateObjectSpace(angles: Vec3): void;

	/**
	 * Orient the layer by specifying the position where the layer should point to (center) and the
	 * directional vector that describes the up axis of the layer (up, default '0 1 0').
	 */
	lookAt(center: Vec3, up?: Vec3): void;

	/**
	 * Orient the layer by specifying the position where the layer should point to (center) and the
	 * directional vector that describes the up axis of the layer (up, default '0 1 0'). This version of lookAt will only adjust the heading and up axis
	 * but won't let the layer face down or up.
	 */
	lookAtYaw(center: Vec3, up?: Vec3): void;

	/**
	 * Changes the parent of the layer. Pass undefined for the parent to remove the parent.
	 * Enable adjustTransforms if you want the layer to stay in place, this will update the local transforms to reflect the old position
	 * relative to the new parent.
	 */
	setParent(parent: String|Number|ILayer, adjustTransforms?: Boolean): void;

	/**
	 * Changes the parent of the layer. Pass undefined for the parent to remove the parent.
	 * Enable adjustTransforms if you want the layer to stay in place, this will update the local transforms to reflect the old position
	 * relative to the new parent. Use attachment to specify a puppet attachment point to attach to.
	 */
	setParent(parent: String|Number|ILayer, attachment: String|Number, adjustTransform?: Boolean): void;

	/**
	 * Returns the current parent layer or undefined if the layer is not parented.
	 */
	getParent(): ILayer;

	/**
	 * Returns an array with all children of this layer
	 */
	getChildren(): [ILayer];

	/**
	 * Get index of an attachment by name.
	 */
	getAttachmentIndex(name: String): Number;

	/**
	 * Get world transform matrix of an attachment.
	 */
	getAttachmentMatrix(attachment: String|Number): Mat4;

	/**
	 * Get world origin of an attachment.
	 */
	getAttachmentOrigin(attachment: String|Number): Vec3;

	/**
	 * Get world angles of an attachment.
	 */
	getAttachmentAngles(attachment: String|Number): Vec3;
}

/**
 * Reference to layer this script runs on.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/ILayer
 */
declare let thisLayer: ILayer;

/**
 * Controls the entire scene and provides access to layers.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IScene
 */
interface IScene {
	/**
	 * Find a specific layer by its editor name, index or ID.
	 */
	getLayer(name: String|Number): ILayer;

	/**
	 * Find a specific layer by its ID.
	 */
	getLayerByID(id: String): ILayer;

	/**
	 * Get current number of layers.
	 */
	getLayerCount(): Number;

	/**
	 * Lists all layers in an array.
	 */
	enumerateLayers(): [ILayer];

	/**
	 * Remove a layer by name, index or object. The layer is removed after all scripts on that frame updated.
	 */
	destroyLayer(layer: String|Number|ILayer): Boolean;

	/**
	 * Creates a new layer. Make sure to register the required asset in IEngine or it won't be pushed to the Workshop when publishing.
	 * The configuration can be an asset handle, a string path, or a full configuration object containing layer properties.
	 * Using a configuration object allows you to set initial values for properties such as `origin`, `angles`, `scale`, `text`, `color`.
	 * in a single call. You can also pass Vec3 objects for `origin`, `angles` or `scale` or reference the current layer via `thisLayer` to take
	 * the current layer as a starting point for these properties.
	 * * Example:
	 * ```javascript
	let newLayer = thisScene.createLayer({
		name: "Layer Name",
		origin: thisLayer.origin,
		angles: thisLayer.angles,
		scale: thisLayer.scale
	});
	```
	 * * For custom geometry, you can optionally include a `model` property referencing an IModelData object or just pass IModelData as a single argument.
	 * * For model-based layers, you likely also want to set perspective to `true` for true 3D rendering (including in 2D scenes).
	 * * Also keep in mind that you should destroy these layers again if you are done using them, they won't destroy themselves and may reduce performance.
	 * @param configuration A string asset path, an IAssetHandle, or an object containing initial layer properties.
	 */
	createLayer(configuration: String|Object|IAssetHandle|IModelData): ILayer;

	/**
	 * Sort layer differently by inserting it at a new index.
	 */
	sortLayer(layer: String|Number|ILayer, index: Number): Boolean;

	/**
	 * Get a layer's index via the layer name.
	 */
	getLayerIndex(layer: String|ILayer): Number;

	/**
	 * Get the initial configuration of an existing layer.
	 */
	getInitialLayerConfig(layer: String|Number|ILayer): Object;

	/**
	 * Get current static scene camera transforms.
	 */
	getCameraTransforms(): CameraTransforms;

	/**
	 * Set current static scene camera transforms.
	 */
	setCameraTransforms(cameraTransforms: CameraTransforms): void;

	/**
	 * Get an animation object by name from any layer.
	 */
	getAnimation(name?: String): IAnimation;

	/**
	 * Create custom model geometry that can be used on a model layer.
	 * Create model layer using `thisScene.createLayer({model: modelDataObject})`.
	 * We recommend attaching the script to the visibility property of a Transform Layer.
	 * If a model is to be used across multiple layers, simply re-use the same ModelData object.
	 * The configuration object is as follow:
	 * It contains a member `shapes` that is an array of one or multiple shape configs.
	 * * Optional Bounding Box (Animation Only):
	 * You may include two Vec3 members, `boundingBoxMins` and `boundingBoxMaxs`, to configure the bounding box
	 * used for hit detection and frustum culling. These are only necessary if you are animating the model
	 * geometry; otherwise, they should be skipped entirely.
	 * * Shape geometry assumes that triangles are being rendered with a counter-clockwise (CCW) winding order.
	 * @param `configuration`: An object containing a `shapes` array and optional bounding box vectors.
	 * A shape config contains the following members:
	 * @param shape.`vertexBuffer`: A Float32Array containing the vertex data in the layout defined by `vertexFormat`.
	 * * You MUST assume a 2D wallpaper context by default, where 1 unit = 1 pixel. Vertex positions are based on screen resolution (e.g., hundreds or thousands of pixels).
	 * * Do NOT use a 0.0 - 1.0 positional scale unless in a 3D wallpaper context, even if the shape that is to be generated is a 3D shape (like a cube or pyramid).
	 * @param shape.`indexBuffer` (optional): A UInt32Array or UInt16Array containing indices into the vertex buffer to render triangles.
	 * @param shape.vertexFormat: An array of the const values POSITION, NORMAL, TANGENT_SIGNED, UV and COLOR of IModelData. Do not use strings directly.
	 * * The order must strictly match the order above, which also needs to match the order in the vertex buffer.
	 * * You may only enable/disable components but not reorder them. For the default model material, use: [IModelData.POSITION, IModelData.NORMAL, IModelData.UV].
	 * * CRITICAL PBR NOTE: If the assigned material utilizes optional features like normal mapping or reflection, the shader requires a Tangent vector. You then must include IModelData.TANGENT_SIGNED.
	 * @param shape.`material`: An IAssetHandle to a new material created in the asset menu of the editor.
	 * * It gets registered with a global engine.registerAsset('materials/FILENAME.json', true) to ensure that it will be precached on wallpaper load.
	 * @param shape.`isVertexBufferDynamic`: Should be set to true ONLY if you intend to change the vertex buffer regularly with IModelData.update().
	 * * This ensures it is allocated as a dynamic buffer on the GPU for better performance. If you do not use update(), this can be omitted.
	 * @param shape.`isIndexBufferDynamic`: Should be set to true ONLY if you intend to change the index buffer regularly with IModelData.update().
	 * * This ensures it is allocated as a dynamic buffer on the GPU for better performance. If you do not use update(), this can be omitted.
	 */
	createModelData(configuration: Object): IModelData;

	/**
	 * Destroy model data that is not needed anymore.
	 * If a layer still exists that is using this model, it will be deleted once that layer is removed.
	 */
	destroyModelData(modelDataHandle: IModelData);

	bloom: Boolean;
	bloomstrength: Number;
	bloomthreshold: Number;

	clearenabled: Boolean;
	clearcolor: Vec3;

	ambientcolor: Vec3;
	skylightcolor: Vec3;

	fov: Number;
	nearz: Number;
	farz: Number;

	camerafade: Boolean;

	camerashake: Boolean;
	camerashakespeed: Number;
	camerashakeamplitude: Number;
	camerashakeroughness: Number;

	cameraparallax: Boolean;
	cameraparallaxamount: Number;
	cameraparallaxdelay: Number;
	cameraparallaxmouseinfluence: Number;
}

/**
 * Reference to the currently active scene.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IScene
 */
declare let thisScene: IScene;

/**
 * Global console interface to log messages.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IConsole
 */
interface IConsole {
	/**
	 * Logs an info message.
	 */
	log(...name: any): void;

	/**
	 * Logs an error message.
	 */
	error(...name: any): void;
}

/**
 * Reference to the global console.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IConsole
 */
declare let console: IConsole;

/**
 * Global context interface to access render state.
 */
interface IRenderContext {
}

/**
 * Reference to the global render context.
 */
declare let renderContext: IRenderContext;

/**
 * Global interface to access input devices.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IInput
 */
interface IInput {
	/**
	 * Position of the cursor in world space. Only x and y are supported right now.
	 */
	cursorWorldPosition: Vec3;

	/**
	 * Position of the cursor on the screen in pixels.
	 */
	cursorScreenPosition: Vec2;

	/**
	 * Whether left cursor button is down.
	 */
	cursorLeftDown: Boolean;
}

/**
 * Reference to global input object.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IInput
 */
declare let input: IInput;

/**
 * Global interface to local storage.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/ILocalStorage
 */
interface ILocalStorage {
	/**
	 * Store settings so that all instances of the wallpaper can access them.
	 */
	static readonly LOCATION_GLOBAL: String = 'global';

	/**
	 * Store settings per screen, like wallpaper properties.
	 */
	static readonly LOCATION_SCREEN: String = 'screen';

	/**
	 * Store new value. Location can be 'screen' to store values per wallpaper instance on multi screen setups or 'global' to share them between all instances. Default is 'screen'.
	 */
	set(key: String, value: Any, location?: String): void;

	/**
	 * Read stored value. Location can be 'screen' to read values per wallpaper instance on multi screen setups or 'global' to share them between all instances. Default is 'screen'.
	 */
	get(key: String, location?: String): Any;

	/**
	 * Remove value from storage. See get/set for locations.
	 */
	delete(key: String, location?: String): Boolean;

	/**
	 * Remove all values from the storage. See get/set for locations.
	 */
	clear(location?: String): void;
}

/**
 * Reference to global local storage object.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/ILocalStorage
 */
declare let localStorage: ILocalStorage;

/**
 * Global system interface for generic commands.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IEngine
 */
interface IEngine {
	/**
	 * Check if the script is running in the editor.
	 */
	isRunningInEditor(): Boolean;

	/**
	 * Returns true if the display of the wallpaper uses a portrait resolution.
	 */
	isPortrait(): Boolean;

	/**
	 * Returns true if the display of the wallpaper uses a landscape resolution.
	 */
	isLandscape(): Boolean;

	/**
	 * Returns true if running on a desktop computer.
	 */
	isDesktopDevice(): Boolean;

	/**
	 * Returns true if running on a mobile device.
	 */
	isMobileDevice(): Boolean;

	/**
	 * Returns true if running as a wallpaper
	 */
	isWallpaper(): Boolean;

	/**
	 * Returns true if running as a screensaver
	 */
	isScreensaver(): Boolean;

	/**
	 * Resolution option for registerAudioBuffers.
	 */
	readonly AUDIO_RESOLUTION_16: Number = 16;

	/**
	 * Resolution option for registerAudioBuffers.
	 */
	readonly AUDIO_RESOLUTION_32: Number = 32;

	/**
	 * Resolution option for registerAudioBuffers.
	 */
	readonly AUDIO_RESOLUTION_64: Number = 64;

	/**
	 * Register this script for listening to audio buffers. Must be called from the global context in a script.
	 * @param resolution Must be either engine.AUDIO_RESOLUTION_16, engine.AUDIO_RESOLUTION_32 or engine.AUDIO_RESOLUTION_64. Defines the size of the buffer per channel.
	 */
	registerAudioBuffers(resolution: Number): AudioBuffers;

/**
	 * Load an asset to be used in a SceneScript-based layer creation.
	 * This function MUST be called at the root global level of the script.
	 * Do NOT place `engine.registerAsset()` inside `init()`, `update()`, or ANY other event function. If you put this inside a function, the asset will fail to load and the script will break.
	 * @param precache optionally also load the material immediately on scene load.
	 */
	registerAsset(file: String, precache: Boolean): IAssetHandle;

	/**
	 * Starts a timeout callback in milliseconds. Returns a new callback that can be used to stop the timeout prematurely.
	 */
	setTimeout(callback: Function, delay?: Number): Function;

	/**
	 * Starts a repeating interval callback in milliseconds. Returns a new callback that can be used to stop the interval.
	 */
	setInterval(callback: Function, delay?: Number): Function;

	/**
	 * Open a user shortcut registered to a user property.
	 */
	openUserShortcut(userPropertyName: String): Boolean;

	/**
	 * Clears a timeout that has been registered previously.
	 * Not implemented. Use returned function to clear.
	 */
	//clearTimeout(callback: Function): Boolean;

	/**
	 * Screen resolution in pixels.
	 */
	screenResolution: Vec2;

	/**
	 * Size of the canvas/full wallpaper in pixels (2D scenes only).
	 */
	canvasSize: Vec2;

	/**
	 * Current user properties.
	 */
	userProperties: Object;

	/**
	 * 24h clock in range [0, 1].
	 */
	timeOfDay: Number;

	/**
	 * Last frametime in seconds. May be zero when the frame needs to be re-drawn without animating.
	 */
	frametime: Number;

	/**
	 * Time the scene has been running.
	 */
	runtime: Number;
}

/**
 * Reference to the global engine object.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IEngine
 */
declare let engine: IEngine;

/**
 * A generic property animation.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/IAnimation
 */
interface IAnimation {
	/**
	 * The framerate of the animation.
	 */
	readonly fps: Number;

	/**
	 * Returns the number of frames of the entire animation.
	 */
	readonly frameCount: Number;

	/**
	 * The duration of the animation.
	 */
	readonly duration: Number;

	/**
	 * The custom name of the animation.
	 */
	readonly name: String;

	/**
	 * Speed factor of the texture animation.
	 */
	rate: Number;

	/**
	 * Start playing the animation if it's paused or stopped.
	 */
	play(): void;

	/**
	 * Pause the animation.
	 */
	pause(): void;

	/**
	 * Stop the animation and reset the current time to zero.
	 */
	stop(): void;

	/**
	 * Checks if the animation is currently playing.
	 */
	isPlaying(): Boolean;

	/**
	 * Returns the current frame of the animation.
	 */
	getFrame(): Number;

	/**
	 * Changes the frame that is currently displayed.
	 */
	setFrame(frame: Number): void;
}

/**
 * Reference to the global shared object.
 * https://docs.wallpaperengine.io/scene/scenescript/reference/class/Shared
 */
declare let shared: Object;