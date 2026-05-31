package com.example.flutter_native_charts

import android.opengl.GLES30
import android.opengl.GLSurfaceView
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

private const val TAG = "ChartRenderer"

// Default clear color — engine-driven once the style is uploaded.
private const val CLEAR_R = 11f / 255f
private const val CLEAR_G = 14f / 255f
private const val CLEAR_B = 20f / 255f

private const val BYTES_PER_FLOAT = 4
private const val FLOATS_PER_VERTEX = 6
private const val STRIDE = FLOATS_PER_VERTEX * BYTES_PER_FLOAT

private const val ATTR_POS_OFFSET = 0
private const val ATTR_COLOR_OFFSET = 2 * BYTES_PER_FLOAT

private const val PRIM_TRIANGLES = 0
private const val PRIM_LINES = 1
private const val PRIM_LINE_STRIP = 2
private const val PRIM_TRIANGLE_STRIP = 3

private const val VERTEX_SHADER_SRC = """#version 300 es
in vec2 a_Position;
in vec4 a_Color;
uniform mat4 u_Projection;
out vec4 v_Color;
void main() {
    gl_Position = u_Projection * vec4(a_Position, 0.0, 1.0);
    v_Color = a_Color;
}
"""

private const val FRAGMENT_SHADER_SRC = """#version 300 es
precision mediump float;
in vec4 v_Color;
out vec4 fragColor;
void main() {
    fragColor = v_Color;
}
"""

private class PassEntry {
    var vertices: FloatArray = FloatArray(0)
    var vertexCount: Int = 0
    var primitive: Int = PRIM_TRIANGLES
}

/**
 * Renderer that drives all geometry from the native ChartEngine. Supports an
 * arbitrary number of passes (currently up to 4: grid, body, wick, crosshair)
 * and uploads them as a single combined VBO.
 */
class ChartRenderer(
    private val chartEngineHandle: Long,
    private val viewportHandle: Long,
) : GLSurfaceView.Renderer {
    private var program: Int = 0
    private var positionAttribLocation: Int = -1
    private var colorAttribLocation: Int = -1
    private var projectionUniformLocation: Int = -1
    private val vbo = IntArray(1)

    private val projectionMatrix = FloatArray(16)
    private val primitiveOut = IntArray(1)

    private val passes = mutableListOf<PassEntry>()
    private var lastSeenGeneration = -1
    private var lastSeenStyleRevision = -1L
    private var lastSeenViewportRevision = -1L

    // Scratch buffer for pulling the engine's style each time it changes.
    // Layout: [0..3] = bg_color RGBA; the other 50 floats are unused by the
    // renderer (they describe the geometry that the engine has already baked
    // into the vertex stream).
    private val styleFloats = FloatArray(54)

    private var uploadBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(0)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()

    @Volatile private var clearR = CLEAR_R
    @Volatile private var clearG = CLEAR_G
    @Volatile private var clearB = CLEAR_B

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES30.glClearColor(clearR, clearG, clearB, 1f)
        GLES30.glEnable(GLES30.GL_BLEND)
        GLES30.glBlendFunc(GLES30.GL_SRC_ALPHA, GLES30.GL_ONE_MINUS_SRC_ALPHA)

        val vertexShader = compileShader(GLES30.GL_VERTEX_SHADER, VERTEX_SHADER_SRC)
        val fragmentShader = compileShader(GLES30.GL_FRAGMENT_SHADER, FRAGMENT_SHADER_SRC)
        program = linkProgram(vertexShader, fragmentShader)

        GLES30.glDeleteShader(vertexShader)
        GLES30.glDeleteShader(fragmentShader)

        positionAttribLocation = GLES30.glGetAttribLocation(program, "a_Position")
        colorAttribLocation = GLES30.glGetAttribLocation(program, "a_Color")
        projectionUniformLocation = GLES30.glGetUniformLocation(program, "u_Projection")

        GLES30.glGenBuffers(1, vbo, 0)
        lastSeenGeneration = -1
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES30.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        if (chartEngineHandle != 0L) {
            val styleRev = ChartEngineJni.nativeStyleRevision(chartEngineHandle)
            if (styleRev != lastSeenStyleRevision) {
                lastSeenStyleRevision = styleRev
                ChartEngineJni.nativeGetStyleFloats(chartEngineHandle, styleFloats)
                clearR = styleFloats[0]
                clearG = styleFloats[1]
                clearB = styleFloats[2]
            }
        }
        GLES30.glClearColor(clearR, clearG, clearB, 1f)
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT)
        if (program == 0 || chartEngineHandle == 0L) return

        val vpRev = ChartEngineJni.nativeViewportRevision(chartEngineHandle)
        if (vpRev != lastSeenViewportRevision) {
            lastSeenViewportRevision = vpRev
            ChartEngineJni.nativeRebuildForViewport(chartEngineHandle)
        }

        val gen = ChartEngineJni.nativeGeneration(chartEngineHandle)
        if (gen != lastSeenGeneration) {
            syncGeometryFromEngine()
            lastSeenGeneration = gen
        }

        GLES30.glUseProgram(program)

        if (viewportHandle != 0L && projectionUniformLocation >= 0) {
            ViewportEngineJni.nativeGetProjectionMatrix(viewportHandle, projectionMatrix)
            GLES30.glUniformMatrix4fv(projectionUniformLocation, 1, false, projectionMatrix, 0)
        }

        if (passes.isEmpty()) return

        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vbo[0])
        GLES30.glEnableVertexAttribArray(positionAttribLocation)
        GLES30.glEnableVertexAttribArray(colorAttribLocation)
        GLES30.glVertexAttribPointer(
            positionAttribLocation, 2, GLES30.GL_FLOAT, false, STRIDE, ATTR_POS_OFFSET,
        )
        GLES30.glVertexAttribPointer(
            colorAttribLocation, 4, GLES30.GL_FLOAT, false, STRIDE, ATTR_COLOR_OFFSET,
        )

        var offset = 0
        for (p in passes) {
            if (p.vertexCount > 0) {
                GLES30.glDrawArrays(toGlPrimitive(p.primitive), offset, p.vertexCount)
                offset += p.vertexCount
            }
        }

        GLES30.glDisableVertexAttribArray(positionAttribLocation)
        GLES30.glDisableVertexAttribArray(colorAttribLocation)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, 0)
    }

    private fun syncGeometryFromEngine() {
        val passCount = ChartEngineJni.nativePassCount(chartEngineHandle)
        // Grow/shrink passes list.
        while (passes.size < passCount) passes.add(PassEntry())
        // Read each pass.
        var totalVertices = 0
        for (i in 0 until passCount) {
            val entry = passes[i]
            val needed = ChartEngineJni.nativeReadPass(
                chartEngineHandle, i, primitiveOut, null,
            )
            if (needed <= 0) {
                entry.vertexCount = 0
                continue
            }
            val requiredFloats = needed * FLOATS_PER_VERTEX
            if (entry.vertices.size < requiredFloats) {
                entry.vertices = FloatArray(requiredFloats + 1024)
            }
            entry.vertexCount = ChartEngineJni.nativeReadPass(
                chartEngineHandle, i, primitiveOut, entry.vertices,
            )
            entry.primitive = primitiveOut[0]
            totalVertices += entry.vertexCount
        }
        // Zero out trailing passes (engine may have dropped some).
        for (i in passCount until passes.size) {
            passes[i].vertexCount = 0
        }

        if (totalVertices == 0) return
        uploadCombinedVbo(totalVertices)
    }

    private fun uploadCombinedVbo(totalVertices: Int) {
        val totalFloats = totalVertices * FLOATS_PER_VERTEX
        val totalBytes = totalFloats * BYTES_PER_FLOAT

        if (uploadBuffer.capacity() < totalFloats) {
            uploadBuffer = ByteBuffer
                .allocateDirect(totalBytes + 4096)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
        }
        uploadBuffer.position(0)
        uploadBuffer.limit(totalFloats)
        for (p in passes) {
            if (p.vertexCount > 0) {
                uploadBuffer.put(p.vertices, 0, p.vertexCount * FLOATS_PER_VERTEX)
            }
        }
        uploadBuffer.position(0)

        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vbo[0])
        GLES30.glBufferData(
            GLES30.GL_ARRAY_BUFFER,
            totalBytes,
            uploadBuffer,
            GLES30.GL_DYNAMIC_DRAW,
        )
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, 0)
    }

    private fun toGlPrimitive(p: Int): Int = when (p) {
        PRIM_TRIANGLES -> GLES30.GL_TRIANGLES
        PRIM_LINES -> GLES30.GL_LINES
        PRIM_LINE_STRIP -> GLES30.GL_LINE_STRIP
        PRIM_TRIANGLE_STRIP -> GLES30.GL_TRIANGLE_STRIP
        else -> GLES30.GL_TRIANGLES
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        if (shader == 0) throw RuntimeException("glCreateShader failed for type=$type")
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)
        val status = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES30.glGetShaderInfoLog(shader)
            GLES30.glDeleteShader(shader)
            Log.e(TAG, "Shader compile failed: $log")
            throw RuntimeException("Shader compile failed: $log")
        }
        return shader
    }

    private fun linkProgram(vs: Int, fs: Int): Int {
        val program = GLES30.glCreateProgram()
        if (program == 0) throw RuntimeException("glCreateProgram failed")
        GLES30.glAttachShader(program, vs)
        GLES30.glAttachShader(program, fs)
        GLES30.glLinkProgram(program)
        val status = IntArray(1)
        GLES30.glGetProgramiv(program, GLES30.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES30.glGetProgramInfoLog(program)
            GLES30.glDeleteProgram(program)
            Log.e(TAG, "Program link failed: $log")
            throw RuntimeException("Program link failed: $log")
        }
        return program
    }
}
