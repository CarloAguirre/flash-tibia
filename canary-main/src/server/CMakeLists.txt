target_sources(
    ${CORE_TARGET_NAME}
    PRIVATE network/connection/connection.cpp
            network/ai_gateway/ai_gateway.cpp
            network/message/networkmessage.cpp
            network/message/outputmessage.cpp
            network/protocol/protocol.cpp
            network/protocol/protocolgame.cpp
            network/protocol/protocollogin.cpp
            network/protocol/protocolstatus.cpp
            network/webhook/webhook.cpp
            server.cpp
            signals.cpp
)
