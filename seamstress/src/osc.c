#include <lo/lo.h>
#include "event_types.h"
#include "events.h"
#include "osc.h"
#include "args.h"

#include <dns_sd.h>
#include <stdio.h>
#include <string.h>

static lo_server_thread server_thread;

static DNSServiceRef dnssd_ref;

static int osc_receive(const char *path, const char *types, lo_arg **argv, int argc, lo_message msg, void *user_data);
static void lo_error_handler(int num, const char *m, const char *path);

void osc_init(void) {
  server_thread = lo_server_thread_new(args_local_port(), lo_error_handler);
  lo_server_thread_add_method(server_thread, NULL, NULL, osc_receive, NULL);
  lo_server_thread_start(server_thread);

  DNSServiceRegister(&dnssd_ref, 0, 0, "seamstress", "_osc._udp", NULL, NULL, htons(lo_server_thread_get_port(server_thread)), 0, NULL, NULL, NULL);
}

void osc_deinit(void) {
  DNSServiceRefDeallocate(dnssd_ref);
  lo_server_thread_free(server_thread);
}

void osc_send(const char *host, const char *port, const char *path, lo_message msg) {
  lo_address address = lo_address_new(host, port);
  if (!address) {
    fprintf(stderr, "failed to create lo_address\n");
    return;
  }
  lo_send_message(address, path, msg);
  lo_address_free(address);
}

int osc_receive(const char *path, const char *types, lo_arg **argv, int argc, lo_message msg, void *user_data) {
  (void)types;
  (void)argv;
  (void)argc;
  (void)user_data;

  union event_data *ev = event_data_new(EVENT_OSC);

  ev->osc_event.path = strdup(path);
  ev->osc_event.msg = lo_message_clone(msg);
  
  lo_address source = lo_message_get_source(msg);
  const char *host = lo_address_get_hostname(source);
  const char *port = lo_address_get_port(source);

  ev->osc_event.from_host = strdup(host);
  ev->osc_event.from_port = strdup(port);

  event_post(ev);
  return 0;
}

void lo_error_handler(int num, const char *m, const char *path) {
  fprintf(stderr, "liblo error %d in path %s: %s\n", num, path, m);
}
