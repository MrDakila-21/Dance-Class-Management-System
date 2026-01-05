-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Jan 04, 2026 at 07:02 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `dance_studio`
--

-- --------------------------------------------------------

--
-- Table structure for table `bookings`
--

CREATE TABLE `bookings` (
  `booking_id` int(11) NOT NULL,
  `class_id` int(11) NOT NULL,
  `customer_name` varchar(100) NOT NULL,
  `contact` varchar(100) DEFAULT NULL,
  `slots_booked` int(11) NOT NULL DEFAULT 1,
  `date_booked` timestamp NOT NULL DEFAULT current_timestamp(),
  `status` enum('Booked','Cancelled','Attended') DEFAULT 'Booked',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `customer_type` varchar(20) NOT NULL DEFAULT 'Regular',
  `booking_ref` varchar(100) DEFAULT NULL,
  `archived` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `bookings`
--

INSERT INTO `bookings` (`booking_id`, `class_id`, `customer_name`, `contact`, `slots_booked`, `date_booked`, `status`, `created_at`, `customer_type`, `booking_ref`, `archived`) VALUES
(1, 1, 'Emily Johnson', 'emily2@email.com', 2, '2025-12-11 08:49:46', 'Booked', '2025-12-11 08:49:46', 'Regular', NULL, 1),
(2, 1, 'Michael Chen', '555-0123', 1, '2025-12-11 08:49:46', 'Booked', '2025-12-11 08:49:46', 'Regular', NULL, 1),
(4, 3, 'David Brown', 'david@email.com', 1, '2025-12-11 08:49:46', 'Booked', '2025-12-11 08:49:46', 'Regular', NULL, 1),
(8, 7, 'earl', 'n/a', 4, '2025-12-18 05:21:50', 'Cancelled', '2025-12-18 05:21:50', 'Member', NULL, 1),
(9, 1, 'ledy', 'n/a', 2, '2025-12-18 06:12:00', 'Booked', '2025-12-18 06:12:00', 'Regular', NULL, 1),
(10, 2, 'mineva', 'No contact info', 14, '2025-12-18 06:12:22', 'Booked', '2025-12-18 06:12:22', 'Regular', NULL, 1),
(11, 8, 'Klang', 'n/a', 2, '2025-12-19 17:02:00', 'Booked', '2025-12-19 17:02:00', 'Regular', 'ST-20251220010200-4446', 1),
(12, 8, 'salamanca', '09122', 1, '2025-12-19 17:08:57', 'Booked', '2025-12-19 17:08:57', 'Regular', 'ST-20251220010857-2560', 1),
(13, 8, 'try', 'sanagumana@gmail.com', 1, '2025-12-19 17:29:12', 'Booked', '2025-12-19 17:29:12', 'Member', 'ST-20251220012912-5200', 1),
(14, 8, 'brent', 'n/a', 2, '2025-12-19 17:46:59', 'Booked', '2025-12-19 17:46:59', 'Regular', 'ST-20251220014659-2742', 1),
(15, 8, 'AZ Martinez', 'n/a', 1, '2025-12-19 17:53:08', 'Booked', '2025-12-19 17:53:08', 'Regular', 'ST-20251220015308-7051', 1),
(16, 11, 'Melai', 'n/a', 2, '2025-12-23 06:09:46', '', '2025-12-23 06:09:46', 'Regular', 'ST-20251223140946-4633', 1),
(18, 10, 'Naruto', 'n/a', 1, '2025-12-25 13:36:22', '', '2025-12-25 13:36:22', 'Regular', 'ST-20251225213622-6058', 0),
(19, 13, 'Sasuke', 'n/a', 1, '2025-12-25 14:18:07', '', '2025-12-25 14:18:07', 'Regular', 'ST-20251225221807-8202', 1),
(20, 13, 'Sakura', 'n/a', 1, '2025-12-25 14:18:40', 'Attended', '2025-12-25 14:18:40', 'Regular', 'ST-20251225221839-1378', 1),
(21, 13, 'wanwan', 'n/a', 1, '2025-12-25 14:21:46', 'Booked', '2025-12-25 14:21:46', 'Regular', 'ST-20251225222146-2534', 1),
(22, 10, 'harith', 'No contact info', 1, '2025-12-25 14:22:39', 'Cancelled', '2025-12-25 14:22:39', 'Regular', 'ST-20251225222239-4633', 0),
(23, 13, 'Orochimaru', 'n/a', 1, '2025-12-25 14:41:49', 'Attended', '2025-12-25 14:41:49', 'Regular', 'ST-20251225224149-5791', 1),
(24, 13, 'Konan', 'n/a', 1, '2025-12-25 14:42:16', 'Attended', '2025-12-25 14:42:16', 'Regular', 'ST-20251225224216-7074', 1),
(25, 13, 'Tsunade', 'n/a', 1, '2025-12-25 14:48:41', 'Attended', '2025-12-25 14:48:41', 'Regular', 'ST-20251225224841-6587', 1),
(26, 10, 'sasori', 'n/a', 1, '2025-12-25 14:53:15', 'Booked', '2025-12-25 14:53:15', 'Regular', 'ST-20251225225315-2422', 0);

--
-- Triggers `bookings`
--
DELIMITER $$
CREATE TRIGGER `update_class_status` AFTER INSERT ON `bookings` FOR EACH ROW BEGIN
    IF NEW.status = 'Booked' THEN
        UPDATE classes 
        SET slots_remaining = slots_remaining - NEW.slots_booked
        WHERE class_id = NEW.class_id;
    END IF;
    
    UPDATE classes 
    SET status = CASE 
        WHEN slots_remaining <= 0 THEN 'Full'
        WHEN slots_remaining <= (total_slots * 0.3) THEN 'Few Slots'
        ELSE 'Available'
    END
    WHERE class_id = NEW.class_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `update_on_cancellation` AFTER UPDATE ON `bookings` FOR EACH ROW BEGIN
    IF OLD.status = 'Booked' AND NEW.status = 'Cancelled' THEN
        UPDATE classes 
        SET slots_remaining = slots_remaining + OLD.slots_booked
        WHERE class_id = NEW.class_id;
        
        UPDATE classes 
        SET status = CASE 
            WHEN slots_remaining <= 0 THEN 'Full'
            WHEN slots_remaining <= (total_slots * 0.3) THEN 'Few Slots'
            ELSE 'Available'
        END
        WHERE class_id = NEW.class_id;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `classes`
--

CREATE TABLE `classes` (
  `class_id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `instructor` varchar(100) NOT NULL,
  `date` date NOT NULL,
  `time` time NOT NULL,
  `duration` int(11) NOT NULL COMMENT 'Minutes',
  `total_slots` int(11) NOT NULL,
  `slots_remaining` int(11) NOT NULL DEFAULT 0,
  `status` enum('Available','Few Slots','Full') DEFAULT 'Available',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `price` decimal(10,2) NOT NULL,
  `archived` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `classes`
--

INSERT INTO `classes` (`class_id`, `title`, `description`, `instructor`, `date`, `time`, `duration`, `total_slots`, `slots_remaining`, `status`, `created_at`, `updated_at`, `price`, `archived`) VALUES
(1, 'Hip Hop Beginner', 'Learn basic hip hop moves and choreography', 'Alice Johnson', '2024-03-15', '18:00:00', 60, 20, 15, 'Available', '2025-12-11 08:49:46', '2025-12-25 13:27:22', 0.00, 1),
(2, 'Ballet Intermediate', 'Intermediate ballet techniques and positions', 'John Smith', '2024-03-20', '16:30:00', 90, 15, 1, 'Few Slots', '2025-12-11 08:49:46', '2025-12-25 13:27:22', 0.00, 1),
(3, 'Salsa Advanced', 'Advanced salsa patterns and partner work', 'Maria Garcia', '2024-03-25', '19:15:00', 75, 20, 19, 'Available', '2025-12-11 08:49:46', '2025-12-25 13:27:22', 0.00, 1),
(7, 'Sample', 'No description', 'Mr. Dakila', '2025-12-18', '02:30:00', 60, 15, 15, 'Available', '2025-12-18 04:24:49', '2025-12-25 13:27:22', 400.00, 1),
(8, 'hehe', 'No description', 'haha', '2025-12-20', '14:20:00', 60, 20, 13, 'Available', '2025-12-19 15:36:32', '2025-12-25 13:27:22', 100.00, 1),
(9, 'kpop', 'ok', 'dakila', '2025-12-19', '18:00:00', 60, 20, 20, 'Available', '2025-12-19 15:37:29', '2025-12-25 13:27:22', 150.00, 1),
(10, 'Folk Dance', 'again', 'Dakila', '2025-12-27', '20:30:00', 60, 20, 19, 'Available', '2025-12-19 15:38:05', '2025-12-25 14:53:15', 100.00, 0),
(11, 'Sample hiphop', 'haha', 'dakila', '2025-12-23', '14:00:00', 60, 15, 15, 'Available', '2025-12-23 05:38:44', '2025-12-25 13:27:22', 100.00, 1),
(13, 'Street Dance', 'n/a', 'Dakila', '2025-12-25', '23:00:00', 60, 20, 19, 'Available', '2025-12-25 14:17:51', '2025-12-25 16:00:29', 150.00, 1),
(14, 'Balerina', 'sige lang', 'Konoha', '2025-12-27', '20:30:00', 60, 20, 20, 'Available', '2025-12-25 15:11:17', '2025-12-25 15:11:17', 150.00, 0);

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `user_id` int(11) NOT NULL,
  `username` varchar(50) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `full_name` varchar(100) NOT NULL,
  `user_role` varchar(20) DEFAULT 'admin',
  `is_active` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_login` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`user_id`, `username`, `password_hash`, `full_name`, `user_role`, `is_active`, `created_at`, `last_login`) VALUES
(1, 'StudioTrack.admin', '$2a$12$LQv3c1yqBWVHxkdU6nZQdeHIXsCYYYvD5uGfP6Oo8b7WqK1lLdKZa', 'StudioTrack Administrator', 'admin', 1, '2025-12-25 15:55:00', '2025-12-25 16:00:29');

--
-- Indexes for dumped tables
--

--
-- Indexes for table `bookings`
--
ALTER TABLE `bookings`
  ADD PRIMARY KEY (`booking_id`),
  ADD KEY `class_id` (`class_id`);

--
-- Indexes for table `classes`
--
ALTER TABLE `classes`
  ADD PRIMARY KEY (`class_id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`user_id`),
  ADD UNIQUE KEY `username` (`username`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `bookings`
--
ALTER TABLE `bookings`
  MODIFY `booking_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=27;

--
-- AUTO_INCREMENT for table `classes`
--
ALTER TABLE `classes`
  MODIFY `class_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `user_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `bookings`
--
ALTER TABLE `bookings`
  ADD CONSTRAINT `bookings_ibfk_1` FOREIGN KEY (`class_id`) REFERENCES `classes` (`class_id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
