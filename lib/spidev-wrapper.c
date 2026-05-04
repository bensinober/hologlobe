// spidev wrapper to use by zig
// not neccessart as zig ioctl functions well enough
// exposed:
//   spi_open(char dev, spi_config_t)
//   spi_close
//   spi_xfer
#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <string.h>

#include <linux/spi/spidev.h>

typedef struct {
    uint8_t mode;
    uint8_t bits_per_word;
    uint32_t speed;
    uint16_t delay;
} spi_config_t;

int spi_open(char *device, spi_config_t config);
int spi_close(int fd);
int spi_xfer(int fd, uint8_t *tx_buffer, uint8_t tx_len, uint8_t *rx_buffer, uint8_t rx_len);
int spi_read(int fd, uint8_t *rx_buffer, uint8_t rx_len);
int spi_write(int fd, uint8_t *tx_buffer, uint8_t tx_len);
void spi_send(int fd, const uint8_t *d, size_t n);

int spi_open(char *device, spi_config_t config) {
    int fd;
    printf("%s\n", device);
    printf("%u\n", config.bits_per_word);
    printf("%lu\n", config.speed);

    /* Open block device */
    fd = open(device, O_RDWR);
    if (fd < 0) {
        return fd;
    }
    uint8_t mode = SPI_MODE_0;
    uint32_t speed = 8000000;
    ioctl(fd, SPI_IOC_WR_MODE, &mode);
    ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed);

    return fd;
}

int spi_close(int fd) {
    return close(fd);
}

int spi_xfer(int fd, uint8_t *tx_buffer, uint8_t tx_len, uint8_t *rx_buffer, uint8_t rx_len) {
    struct spi_ioc_transfer spi_message[1];
    memset(spi_message, 0, sizeof(spi_message));

    spi_message[0].rx_buf = (unsigned long)rx_buffer;
    spi_message[0].tx_buf = (unsigned long)tx_buffer;
    spi_message[0].len = tx_len;

    return ioctl(fd, SPI_IOC_MESSAGE(1), spi_message);
}

void spi_send(int fd, const uint8_t *d, size_t n) {
    if (write(fd, d, n) != (ssize_t)n) {
        perror("SPI write");
    }
}

int spi_read(int fd, uint8_t *rx_buffer, uint8_t rx_len){
    struct spi_ioc_transfer spi_message[1];
    memset(spi_message, 0, sizeof(spi_message));

    spi_message[0].rx_buf = (unsigned long)rx_buffer;
    spi_message[0].len = rx_len;


    return ioctl(fd, SPI_IOC_MESSAGE(1), spi_message);
}

int spi_write(int fd, uint8_t *tx_buffer, uint8_t tx_len){
    struct spi_ioc_transfer spi_message[1];
    memset(spi_message, 0, sizeof(spi_message));

    spi_message[0].tx_buf = (unsigned long)tx_buffer;
    spi_message[0].len = tx_len;

    return ioctl(fd, SPI_IOC_MESSAGE(1), spi_message);
}
