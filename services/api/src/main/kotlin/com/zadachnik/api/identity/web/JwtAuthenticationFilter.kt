package com.zadachnik.api.identity.web

import com.zadachnik.api.common.ApiException
import com.zadachnik.api.identity.application.JwtService
import com.zadachnik.api.identity.domain.UserStatus
import com.zadachnik.api.identity.infrastructure.DeviceRepository
import com.zadachnik.api.identity.infrastructure.UserRepository
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.http.HttpHeaders
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter

@Component
class JwtAuthenticationFilter(
    private val jwt: JwtService,
    private val users: UserRepository,
    private val devices: DeviceRepository,
) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val header = request.getHeader(HttpHeaders.AUTHORIZATION)
        if (header != null && header.startsWith(BEARER_PREFIX, ignoreCase = true)) {
            authenticate(header.substring(BEARER_PREFIX.length).trim())
        }
        filterChain.doFilter(request, response)
    }

    private fun authenticate(token: String) {
        try {
            val claims = jwt.verifyAccess(token)
            val user = users.findById(claims.userId) ?: return
            val device = devices.findById(claims.deviceId) ?: return
            if (user.status != UserStatus.ACTIVE || device.isRevoked || device.userId != user.id) {
                return
            }

            val authentication = UsernamePasswordAuthenticationToken(
                claims.userId.toString(),
                null,
                emptyList(),
            )
            authentication.details = claims.deviceId.toString()
            SecurityContextHolder.getContext().authentication = authentication
        } catch (exception: ApiException) {
            SecurityContextHolder.clearContext()
        }
    }

    companion object {
        private const val BEARER_PREFIX = "Bearer "
    }
}
