package com.zadachnik.api.identity.config

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.common.ApiError
import com.zadachnik.api.common.ApiErrorResponse
import com.zadachnik.api.identity.web.JwtAuthenticationFilter
import java.util.UUID
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.security.web.AuthenticationEntryPoint
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter

@Configuration
@EnableWebSecurity
class SecurityConfiguration(
    private val jwtAuthenticationFilter: JwtAuthenticationFilter,
    private val objectMapper: ObjectMapper,
) {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        http
            .csrf { it.disable() }
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .authorizeHttpRequests { authorize ->
                authorize.requestMatchers(
                    "/api/v1/auth/setup",
                    "/api/v1/auth/login",
                    "/api/v1/auth/refresh",
                    "/api/v1/auth/logout",
                    "/actuator/health",
                    "/actuator/health/**",
                ).permitAll()
                authorize.anyRequest().authenticated()
            }
            .exceptionHandling { it.authenticationEntryPoint(unauthorizedEntryPoint()) }
            .httpBasic { it.disable() }
            .formLogin { it.disable() }
            .logout { it.disable() }
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter::class.java)

        return http.build()
    }

    @Bean
    fun passwordEncoder(): PasswordEncoder = BCryptPasswordEncoder(BCRYPT_STRENGTH)

    private fun unauthorizedEntryPoint(): AuthenticationEntryPoint = AuthenticationEntryPoint { _, response, _ ->
        response.status = 401
        response.contentType = MediaType.APPLICATION_JSON_VALUE
        response.characterEncoding = Charsets.UTF_8.name()
        objectMapper.writeValue(
            response.writer,
            ApiErrorResponse(
                ApiError(
                    code = "UNAUTHENTICATED",
                    message = "Требуется авторизация",
                    requestId = UUID.randomUUID().toString(),
                ),
            ),
        )
    }

    companion object {
        private const val BCRYPT_STRENGTH = 12
    }
}
