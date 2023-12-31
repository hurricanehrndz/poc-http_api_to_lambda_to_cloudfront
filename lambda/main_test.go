package main

import (
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
)

func TestHandler(t *testing.T) {

	tests := []struct {
		request events.APIGatewayV2HTTPRequest
		expect  int
	}{
		{
			// Test that the handler responds with the correct response
			// when a valid name is provided in the HTTP body
			request: events.APIGatewayV2HTTPRequest{RawPath: "/000.jpg"},
			expect:  302,
		},
	}

	for _, test := range tests {
		response, _ := Handler(test.request)
		print(response.Headers["location"])
		assert.Equal(t, 302, response.StatusCode)
	}

}
