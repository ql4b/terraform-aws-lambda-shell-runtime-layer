package main

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

type runtimeAPIClient struct {
	host string
}

func newRuntimeAPIClient(address string) *runtimeAPIClient {
	return &runtimeAPIClient{address}
}

func (c *runtimeAPIClient) getNextInvocation() (string, string, []byte, error) {
	conn, err := net.Dial("tcp", c.host)
	if err != nil {
		return "", "", nil, err
	}
	defer conn.Close()

	fmt.Fprintf(conn, "GET /2018-06-01/runtime/invocation/next HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", c.host)

	reader := bufio.NewReader(conn)
	var requestID string
	var traceID string
	var contentLength int
	var chunked bool

	for {
		line, _ := reader.ReadString('\n')
		lower := strings.ToLower(line)
		if strings.HasPrefix(lower, "lambda-runtime-aws-request-id:") {
			requestID = strings.TrimSpace(line[31:])
		}
		if strings.HasPrefix(lower, "lambda-runtime-trace-id:") {
			traceID = strings.TrimSpace(line[24:])
		}
		if strings.HasPrefix(lower, "content-length:") {
			contentLength, _ = strconv.Atoi(strings.TrimSpace(line[16:]))
		}
		if strings.HasPrefix(lower, "transfer-encoding:") && strings.Contains(lower, "chunked") {
			chunked = true
		}
		if line == "\r\n" {
			break
		}
	}

	var body []byte
	if contentLength > 0 {
		body = make([]byte, contentLength)
		_, err = io.ReadFull(reader, body)
	} else if chunked {
		// Read chunked body
		var chunks []byte
		for {
			sizeLine, _ := reader.ReadString('\n')
			sizeLine = strings.TrimSpace(sizeLine)
			size, _ := strconv.ParseInt(sizeLine, 16, 64)
			if size == 0 {
				break
			}
			chunk := make([]byte, size)
			io.ReadFull(reader, chunk)
			chunks = append(chunks, chunk...)
			reader.ReadString('\n') // consume trailing CRLF
		}
		body = chunks
	} else {
		// Connection: close — read until EOF
		body, err = io.ReadAll(reader)
	}
	if err != nil {
		return "", "", nil, err
	}
	return requestID, traceID, body, nil
}

func (c *runtimeAPIClient) sendResponse(requestID string, response []byte) error {
	conn, err := net.Dial("tcp", c.host)
	if err != nil {
		return err
	}
	defer conn.Close()

	fmt.Fprintf(conn, "POST /2018-06-01/runtime/invocation/%s/response HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", requestID, c.host, len(response), response)

	// Read status line to ensure Runtime API acknowledged
	reader := bufio.NewReader(conn)
	reader.ReadString('\n')
	return nil
}

func (c *runtimeAPIClient) sendError(requestID, errorMsg string) error {
	conn, err := net.Dial("tcp", c.host)
	if err != nil {
		return err
	}
	defer conn.Close()

	errorPayload := `{"errorMessage": "` + errorMsg + `", "errorType": "Runtime.HandlerError"}`
	fmt.Fprintf(conn, "POST /2018-06-01/runtime/invocation/%s/error HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\nConnection: close\r\nLambda-Runtime-Function-Error-Type: Runtime.HandlerError\r\n\r\n%s", requestID, c.host, len(errorPayload), errorPayload)

	reader := bufio.NewReader(conn)
	reader.ReadString('\n')
	return nil
}

func (c *runtimeAPIClient) sendInitError(errorMsg string) error {
	conn, err := net.Dial("tcp", c.host)
	if err != nil {
		return err
	}
	defer conn.Close()

	errorPayload := `{"errorMessage": "` + errorMsg + `", "errorType": "Runtime.NoSuchHandler"}`
	fmt.Fprintf(conn, "POST /2018-06-01/runtime/init/error HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\nLambda-Runtime-Function-Error-Type: Runtime.NoSuchHandler\r\n\r\n%s", c.host, len(errorPayload), errorPayload)
	return nil
}

func executeShellHandler(handlerFile, handlerFunc string, eventData []byte) ([]byte, error) {
	cmd := exec.Command("bash", "-c", "source "+handlerFile+" && "+handlerFunc)
	cmd.Stdin = strings.NewReader(string(eventData))
	cmd.Stderr = os.Stderr
	return cmd.Output()
}

func main() {
	runtimeAPI := os.Getenv("AWS_LAMBDA_RUNTIME_API")
	handler := os.Getenv("_HANDLER")
	if handler == "" {
		handler = "handler.run"
	}
	parts := strings.Split(handler, ".")
	if len(parts) < 2 {
		parts = []string{"handler", "run"}
	}
	handlerFile := parts[0] + ".sh"
	handlerFunc := parts[1]

	client := newRuntimeAPIClient(runtimeAPI)

	if _, err := os.Stat(handlerFile); os.IsNotExist(err) {
		client.sendInitError("Handler file not found: " + handlerFile)
		os.Exit(1)
	}

	for {
		requestID, traceID, eventData, err := client.getNextInvocation()
		if err != nil {
			continue
		}

		if traceID != "" {
			os.Setenv("_X_AMZN_TRACE_ID", traceID)
		}

		response, err := executeShellHandler(handlerFile, handlerFunc, eventData)
		if err != nil {
			client.sendError(requestID, err.Error())
			continue
		}

		client.sendResponse(requestID, response)
	}
}
