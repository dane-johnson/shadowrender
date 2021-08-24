(import
	(chicken bitwise)
	(chicken memory)
	(prefix epoxy "gl:")
	(prefix glfw3 "glfw:")
	srfi-1
	srfi-4
	gl-math
	gl-utils
	glls-render
	assimp
	soil
	miscmacros)

(define cube-mesh (ai-mesh->mesh (get-mesh (import-file "cube.ply") 0)))
(define ball-mesh (ai-mesh->mesh (get-mesh (import-file "ball.ply") 0)))

(define model (make-parameter (mat4-identity #t)))
(define view (make-parameter (camera-inverse (translation #f32(0.0 0.0 10.0)) #t)))
(define projection (make-parameter (perspective 800 600 0.1 100 45 #t)))
(define light-direction (make-parameter (make-point 1.0 0.0 0.0 #t)))
(define flags (make-parameter (make-u32vector 1 0 #t)))

(define (rotate-light x)
	(m*vector! (axis-angle-rotation (make-point 0 1 0) x) (light-direction)))

(let ([x (make-parameter 0)]
			[y (make-parameter 0)])
	(glfw:cursor-position-callback
	 (lambda (window xpos ypos)
		 (let ([rel-x (- xpos (x))]
					 [rel-y (- ypos (y))])
			 (x xpos)
			 (y ypos)
			 (rotate-light (* rel-x 0.01))))))

(define-constant +dark+ #x1)

(define tex (make-parameter #f))

(define-pipeline phong
	((#:vertex #:input ((position #:vec3) (uv #:vec2) (normal #:vec3))
						 #:output ((UV #:vec2) (NORMAL #:vec3))
						 #:uniform ((model #:mat4) (view #:mat4) (projection #:mat4))
						 #:version (330 core))
	 (define (main) #:void
		 (set! gl:position (* projection view model (vec4 position 1.0)))
		 (set! UV uv)
		 (set! NORMAL (vec3 (* model (vec4 normal 1.0))))))
	((#:fragment #:input ((UV #:vec2) (NORMAL #:vec3))
		           #:uniform ((tex #:sampler2D) (flags #:uint) (light-direction #:vec3))
							 #:output ((frag-color #:vec4))
							 #:version (330 core))
	 (%define DARK 0x1U)
	 (define (luma (color #:vec4)) #:float
		 (+ (* (~~ color r) 0.2126)
				(* (~~ color g) 0.7152)
				(* (~~ color b) 0.0722)))
	 (define ambient-pct #:float 0.2)
	 (define diffuse-pct #:float 0.8)
	 (define (main) #:void
		 (define albedo #:vec4 (vec4 (texture tex UV)))
		 (define diffuse #:float (dot (normalize light-direction) (normalize NORMAL)))
		 (define color #:vec4 (* albedo (+ (* (max diffuse 0.0) diffuse-pct) ambient-pct)))
		 (if (or (and (not (bool (bitwise-and flags DARK))) (< (luma color) 0.15))
						 (and (bool (bitwise-and flags DARK)) (> (luma color) 0.15)))
				 (discard))
		 (set! frag-color color))))

(define (update)
	(model
	 (axis-angle-rotation #f32(1.0 0.5 0.2) (glfw:get-time) (model))))

(glfw:with-window (800 600 "Shadowrender"
									 #:client-api glfw:+opengl-api+
									 #:context-version-major 3
									 #:context-version-minor 3
									 #:opengl-profile glfw:+opengl-core-profile+
									 #:resizable #f)
 (gl:enable gl:+depth-test+)
 (gl:enable gl:+cull-face+)
  ;; Textures
 (tex (load-ogl-texture "crate.jpg" force-channels/auto texture-id/create-new-id (bitwise-ior texture/repeats
																																															texture/mipmaps)))
 ;; Pipelines
 (compile-pipelines)
 (for-each (lambda (s) (print (shader-source s))) (pipeline-shaders phong))
 ;; Meshes
 (mesh-make-vao! cube-mesh (pipeline-mesh-attributes phong))
 (mesh-make-vao! ball-mesh (pipeline-mesh-attributes phong))
 (define cube-renderable (make-phong-renderable #:mesh cube-mesh
																								#:flags (flags)
																								#:model (model)
																								#:view (view)
																								#:projection (projection)
																								#:light-direction (light-direction)
																								#:tex (tex)))
 (define ball-renderable (make-phong-renderable #:mesh ball-mesh
																								#:flags (flags)
																								#:model (model)
																								#:view (view)
																								#:projection (projection)
																								#:light-direction (light-direction)
																								#:tex (tex)))
 (until (glfw:window-should-close (glfw:window))
	(update)
	(gl:clear-color 0.0 0.0 0.0 1.0)
	(gl:clear (bitwise-ior gl:+color-buffer-bit+ gl:+depth-buffer-bit+))
	(u32vector-set! (flags) 0 0)
	(render-phong cube-renderable)
	(u32vector-set! (flags) 0 +dark+)
	(render-phong ball-renderable)
	(glfw:swap-buffers (glfw:window))
	(glfw:poll-events)))
